import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#else
import CJavaScriptCore
#endif

// Runs the team's JavaScript from app/ inside the app with JavaScriptCore. js/build.sh bundles it into
// Resources/nt-core.js. Every call goes in and out as JSON, so the numbers that come back are exactly the
// ones the JavaScript made
enum JSCore {
    // A JavaScript error, or an answer that didn't have the shape the Swift side expected. reason is the
    // JavaScript error's own message
    struct Failure: LocalizedError {
        let message: String
        var reason = ""
        var errorDescription: String? { message }
    }

    // Every call runs on this one thread, one at a time, so the engine only ever sees a single thread
    private static let thread: JSThread = {
        let t = JSThread()
        t.start()
        return t
    }()
    private static var engine: (context: JSGlobalContextRef, call: JSObjectRef, callKeep: JSObjectRef)?

    // JSON has no NaN or Infinity, so they travel as these words. core.js turns them back into numbers
    private static let nan = "__ntNaN"
    private static let inf = "__ntInf"
    private static let negInf = "__ntNegInf"

    // In the app nt-core.js is a resource. Swift Package tests find it in Resources, next to Core
    static var bundleURL: URL? {
        if let url = Bundle.main.url(forResource: "nt-core", withExtension: "js") { return url }
        if let path = ProcessInfo.processInfo.environment["NT_CORE_JS"] { return URL(fileURLWithPath: path) }
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent("nt-core.js")
        return FileManager.default.fileExists(atPath: beside.path) ? beside : nil
    }

    // Calls a JavaScript function by its path, like "train.applyTry", or reads a value like "train.TARGETS"
    static func call<T: Decodable>(_ path: String, _ args: any Encodable...) throws -> T {
        try call(path, args: args)
    }

    static func call<T: Decodable>(_ path: String, args: [any Encodable]) throws -> T {
        try decode(Box<T>.self, run(path, args, keep: false), path).v
    }

    // The same, and the result also stays in the JavaScript. Pass JSArg.kept(ref) to hand it back later
    // without sending it again, for things read every frame
    static func keep<T: Decodable>(_ path: String, _ args: any Encodable...) throws -> (value: T, ref: Int) {
        let box = try decode(KeptBox<T>.self, run(path, args, keep: true), path)
        return (value: box.v, ref: box.ref)
    }

    // For calls that only fail if nt-core.js is missing or broken. That stops the app with the reason,
    // the same as a bug in Swift would
    static func must<T: Decodable>(_ path: String, _ args: any Encodable...) -> T {
        do {
            return try call(path, args: args)
        } catch {
            fatalError("NeuroTrace: \(error.localizedDescription)")
        }
    }

    static func mustKeep<T: Decodable>(_ path: String, _ args: any Encodable...) -> (value: T, ref: Int) {
        do {
            let box = try decode(KeptBox<T>.self, run(path, args, keep: true), path)
            return (value: box.v, ref: box.ref)
        } catch {
            fatalError("NeuroTrace: \(error.localizedDescription)")
        }
    }

    // Runs work on the JavaScript thread and waits for it without holding up the screen. For calls slow
    // enough to freeze it, like measuring a whole spiral
    static func background<R>(_ work: @escaping () throws -> R) async throws -> R {
        try await withCheckedThrowingContinuation { done in
            thread.post { done.resume(with: Result { try work() }) }
        }
    }

    // Turns the answer into the Swift shape, naming the call if the shapes don't match
    private static func decode<B: Decodable>(_ type: B.Type, _ data: Data, _ path: String) throws -> B {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw Failure(message: "\(path) gave back something Swift couldn't read. \(error)")
        }
    }

    private struct Box<T: Decodable>: Decodable { let v: T }
    private struct KeptBox<T: Decodable>: Decodable { let v: T; let ref: Int }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: inf, negativeInfinity: negInf, nan: nan)
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: inf, negativeInfinity: negInf, nan: nan)
        return decoder
    }

    private static func run(_ path: String, _ args: [any Encodable], keep: Bool) throws -> Data {
        let json = String(decoding: try encoder().encode(args.map { a in JSArg(a) }), as: UTF8.self)
        return try thread.run { try runHere(path, json, keep: keep) }.get()
    }

    // Only ever runs on the JavaScript thread. JavaScriptCore frees any value it can't find on the stack,
    // and Swift keeps arrays and captured values elsewhere, so every value is protected as soon as it's made
    private static func runHere(_ path: String, _ json: String, keep: Bool) throws -> Data {
        let (context, call, callKeep) = try start()
        let pathValue = protectedString(context, path)
        defer { JSValueUnprotect(context, pathValue) }
        let jsonValue = protectedString(context, json)
        defer { JSValueUnprotect(context, jsonValue) }
        let args = UnsafeMutablePointer<JSValueRef?>.allocate(capacity: 2)
        defer { args.deallocate() }
        args[0] = pathValue
        args[1] = jsonValue
        var exception: JSValueRef? = nil
        let result = JSObjectCallAsFunction(context, keep ? callKeep : call, nil, 2, args, &exception)
        if let exception {
            JSValueProtect(context, exception)
            defer { JSValueUnprotect(context, exception) }
            let reason = errorMessage(context, exception)
            throw Failure(message: "\(path) failed. \(reason)", reason: reason)
        }
        guard let result else { throw Failure(message: "\(path) gave back nothing") }
        JSValueProtect(context, result)
        defer { JSValueUnprotect(context, result) }
        return Data(text(context, result).utf8)
    }

    // A JavaScript string, already protected. Whoever asked for it unprotects it
    private static func protectedString(_ context: JSContextRef, _ s: String) -> JSValueRef? {
        let js = JSStringCreateWithUTF8CString(s)
        defer { JSStringRelease(js) }
        let value = JSValueMakeString(context, js)
        JSValueProtect(context, value)
        return value
    }

    // A JavaScript error's message, without the "Error" in front, or the thrown value as text
    private static func errorMessage(_ context: JSContextRef, _ value: JSValueRef) -> String {
        if JSValueIsObject(context, value), let object = JSValueToObject(context, value, nil) {
            let name = JSStringCreateWithUTF8CString("message")
            defer { JSStringRelease(name) }
            if let message = JSObjectGetProperty(context, object, name, nil), !JSValueIsUndefined(context, message) {
                return text(context, message)
            }
        }
        return text(context, value)
    }

    // Runs some JavaScript and gives back its value, or the error's text if it threw
    private static func evaluate(_ context: JSGlobalContextRef, _ code: String) -> (value: JSValueRef?, error: String?) {
        let script = JSStringCreateWithUTF8CString(code)
        defer { JSStringRelease(script) }
        var exception: JSValueRef? = nil
        let value = JSEvaluateScript(context, script, nil, nil, 1, &exception)
        if let exception {
            JSValueProtect(context, exception)
            defer { JSValueUnprotect(context, exception) }
            return (nil, text(context, exception))
        }
        return (value, nil)
    }

    // Starts the engine and loads nt-core.js the first time it's needed
    private static func start() throws -> (JSGlobalContextRef, JSObjectRef, JSObjectRef) {
        if let engine { return engine }
        guard let url = bundleURL, let code = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure(message: "nt-core.js is missing. Run js/build.sh")
        }
        guard let context = JSGlobalContextCreate(nil) else { throw Failure(message: "JavaScriptCore didn't start") }
        if let error = evaluate(context, code).error { throw Failure(message: "nt-core.js didn't load. \(error)") }
        let made = (context, try function(context, "NT.call"), try function(context, "NT.callKeep"))
        engine = made
        return made
    }

    // A function from the bundle, held so JavaScriptCore never clears it away
    private static func function(_ context: JSGlobalContextRef, _ name: String) throws -> JSObjectRef {
        let found = evaluate(context, name)
        guard found.error == nil, let value = found.value, let object = JSValueToObject(context, value, nil), JSObjectIsFunction(context, object) else {
            throw Failure(message: "nt-core.js has no \(name). Run js/build.sh")
        }
        JSValueProtect(context, object)
        return object
    }

    private static func text(_ context: JSContextRef?, _ value: JSValueRef?) -> String {
        guard let value else { return "" }
        guard let js = JSValueToStringCopy(context, value, nil) else { return "" }
        defer { JSStringRelease(js) }
        let size = JSStringGetMaximumUTF8CStringSize(js)
        var bytes = [CChar](repeating: 0, count: size)
        let written = JSStringGetUTF8CString(js, &bytes, size)
        return String(decoding: bytes.prefix(max(0, written - 1)).map { c in UInt8(bitPattern: c) }, as: UTF8.self)
    }
}

// The thread the JavaScript runs on. Jobs wait their turn, and whoever asked waits for the answer
private final class JSThread {
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var thread: Thread?

    func start() {
        let t = Thread { [unowned self] in self.loop() }
        t.name = "NeuroTrace JavaScript"
        // Room for the interpreter's deeper calls
        t.stackSize = 8 << 20
        thread = t
        t.start()
    }

    private func loop() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
    }

    // Adds a job to the queue without waiting for it
    func post(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    // Runs work on the thread and waits for the answer. On the thread itself it just runs it
    func run<R>(_ work: @escaping () throws -> R) -> Result<R, Error> {
        if let thread, Thread.current == thread { return Result { try work() } }
        let done = DispatchSemaphore(value: 0)
        var answer: Result<R, Error>? = nil
        post {
            answer = Result { try work() }
            done.signal()
        }
        done.wait()
        return answer!
    }
}

// One argument for a JavaScript call. Anything Encodable, or an object kept in the JavaScript by JSCore.keep
struct JSArg: Encodable {
    private let write: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        write = { encoder in try value.encode(to: encoder) }
    }

    static func kept(_ ref: Int) -> JSArg { JSArg(["__ntRef": ref]) }

    func encode(to encoder: Encoder) throws { try write(encoder) }
}

// A drawn point as the JavaScript reads it. Pressure and tilt aren't used there, so they stay behind
struct JSPoint: Encodable {
    var t: Double
    var x: Double
    var y: Double
}

extension Array where Element == Sample {
    var forJS: [JSPoint] { map { s in JSPoint(t: s.t, x: s.x, y: s.y) } }
}

// Any JSON value. For things that are already JSON, like a scoring file or an AI reply, so they reach the
// JavaScript as they are. Kept apart from Any so true and 1 stay different, like in JavaScript
indirect enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    // Foundation's JSON objects, like the dictionaries the tests build, as a JSONValue
    static func from(_ raw: Any) -> JSONValue? {
        guard JSONSerialization.isValidJSONObject(raw) || raw is NSNull,
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
