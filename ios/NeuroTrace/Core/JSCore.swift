// JSCORE.SWIFT RUNS THE TEAM'S JAVASCRIPT INSIDE THE APP WITH JAVASCRIPTCORE
// IT LOADS Resources/nt-core.js, WHICH js/build.sh BUNDLES FROM app/
// EVERY CALL SENDS ITS ARGUMENTS AS JSON AND READS THE ANSWER BACK AS JSON

import Foundation

// Load JavaScriptCore from Apple, or from the C package where Apple's is not there
#if canImport(JavaScriptCore)
import JavaScriptCore
#else
import CJavaScriptCore
#endif

// Starts the JavaScript engine and calls functions in nt-core.js
enum JSCore {

    // A JavaScript error, or an answer Swift couldn't read, where reason is the JavaScript error's own message
    struct Failure: LocalizedError {
        let message: String
        var reason = ""
        var errorDescription: String? { message }
    }

    // The one thread every call runs on, started the first time it is used
    private static let thread: JSThread = {
        let t = JSThread()
        t.start()
        return t
    }()

    // The engine and the two call functions, set once the engine starts
    private static var engine: (context: JSGlobalContextRef, call: JSObjectRef, callKeep: JSObjectRef)?

    // The words NaN and infinity are sent as in JSON, which core.js turns back into numbers
    private static let nan = "__ntNaN"
    private static let inf = "__ntInf"
    private static let negInf = "__ntNegInf"

    // Find nt-core.js in the app, then at the NT_CORE_JS path, then in Resources next to Core
    static var bundleURL: URL? {
        if let url = Bundle.main.url(forResource: "nt-core", withExtension: "js") { return url }
        if let path = ProcessInfo.processInfo.environment["NT_CORE_JS"] { return URL(fileURLWithPath: path) }
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent("nt-core.js")
        return FileManager.default.fileExists(atPath: beside.path) ? beside : nil
    }


    // CALLING THE JAVASCRIPT

    // Call a JavaScript function by its path, like "train.applyTry", or read a value like "train.TARGETS"
    static func call<T: Decodable>(_ path: String, _ args: any Encodable...) throws -> T {
        try call(path, args: args)
    }

    // The same call, with the arguments passed as a list
    static func call<T: Decodable>(_ path: String, args: [any Encodable]) throws -> T {
        try decode(Box<T>.self, run(path, args, keep: false), path).v
    }

    // Call a function and also keep the result in the JavaScript, giving back a ref to it
    // JSArg.kept(ref) passes the kept result into a later call
    static func keep<T: Decodable>(_ path: String, _ args: any Encodable...) throws -> (value: T, ref: Int) {
        let box = try decode(KeptBox<T>.self, run(path, args, keep: true), path)
        return (value: box.v, ref: box.ref)
    }

    // Call a function and stop the app with the error message if the call fails
    static func must<T: Decodable>(_ path: String, _ args: any Encodable...) -> T {
        do {
            return try call(path, args: args)
        } catch {
            fatalError("NeuroTrace: \(error.localizedDescription)")
        }
    }

    // Call a function and keep its result, and stop the app with the error message if the call fails
    static func mustKeep<T: Decodable>(_ path: String, _ args: any Encodable...) -> (value: T, ref: Int) {
        do {
            let box = try decode(KeptBox<T>.self, run(path, args, keep: true), path)
            return (value: box.v, ref: box.ref)
        } catch {
            fatalError("NeuroTrace: \(error.localizedDescription)")
        }
    }

    // Run work on the JavaScript thread and wait for it without blocking the screen
    static func background<R>(_ work: @escaping () throws -> R) async throws -> R {
        try await withCheckedThrowingContinuation { done in
            thread.post { done.resume(with: Result { try work() }) }
        }
    }

    // Read the answer into a Swift type, and throw a Failure that names the call if it can't
    private static func decode<B: Decodable>(_ type: B.Type, _ data: Data, _ path: String) throws -> B {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw Failure(message: "\(path) gave back something Swift couldn't read. \(error)")
        }
    }

    // The answer as the JavaScript wraps it, with the value in v, and the ref for a kept result
    private struct Box<T: Decodable>: Decodable { let v: T }
    private struct KeptBox<T: Decodable>: Decodable { let v: T; let ref: Int }

    // A JSON encoder that writes NaN and infinity as the words above
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: inf, negativeInfinity: negInf, nan: nan)
        return encoder
    }

    // A JSON decoder that reads the words above back as NaN and infinity
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: inf, negativeInfinity: negInf, nan: nan)
        return decoder
    }

    // Turn the arguments into JSON text and run the call on the JavaScript thread
    private static func run(_ path: String, _ args: [any Encodable], keep: Bool) throws -> Data {
        let json = String(decoding: try encoder().encode(args.map { a in JSArg(a) }), as: UTF8.self)
        return try thread.run { try runHere(path, json, keep: keep) }.get()
    }


    // TALKING TO JAVASCRIPTCORE

    // Run one call on the JavaScript thread, protecting every JavaScript value as soon as it is made
    private static func runHere(_ path: String, _ json: String, keep: Bool) throws -> Data {
        let (context, call, callKeep) = try start()

        // Make the path and the JSON as JavaScript strings, and unprotect them when done
        let pathValue = protectedString(context, path)
        defer { JSValueUnprotect(context, pathValue) }
        let jsonValue = protectedString(context, json)
        defer { JSValueUnprotect(context, jsonValue) }

        // Put the two strings in an argument list
        let args = UnsafeMutablePointer<JSValueRef?>.allocate(capacity: 2)
        defer { args.deallocate() }
        args[0] = pathValue
        args[1] = jsonValue

        // Call NT.call, or NT.callKeep when keeping the result
        var exception: JSValueRef? = nil
        let result = JSObjectCallAsFunction(context, keep ? callKeep : call, nil, 2, args, &exception)

        // If the JavaScript threw, throw a Failure with its message
        if let exception {
            JSValueProtect(context, exception)
            defer { JSValueUnprotect(context, exception) }
            let reason = errorMessage(context, exception)
            throw Failure(message: "\(path) failed. \(reason)", reason: reason)
        }

        // Give back the answer's text as data
        guard let result else { throw Failure(message: "\(path) gave back nothing") }
        JSValueProtect(context, result)
        defer { JSValueUnprotect(context, result) }
        return Data(text(context, result).utf8)
    }

    // Make a JavaScript string that is already protected, which the caller unprotects
    private static func protectedString(_ context: JSContextRef, _ s: String) -> JSValueRef? {
        let js = JSStringCreateWithUTF8CString(s)
        defer { JSStringRelease(js) }
        let value = JSValueMakeString(context, js)
        JSValueProtect(context, value)
        return value
    }

    // Give back a JavaScript error's message without the "Error" in front, or the thrown value as text
    private static func errorMessage(_ context: JSContextRef, _ value: JSValueRef) -> String {

        // Read the message property if the value is an object that has one
        if JSValueIsObject(context, value), let object = JSValueToObject(context, value, nil) {
            let name = JSStringCreateWithUTF8CString("message")
            defer { JSStringRelease(name) }
            if let message = JSObjectGetProperty(context, object, name, nil), !JSValueIsUndefined(context, message) {
                return text(context, message)
            }
        }

        // Otherwise give back the value as text
        return text(context, value)
    }

    // Run some JavaScript and give back its value, or the error's text if it threw
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

    // Start the engine and load nt-core.js the first time, then give back the same engine every time after
    private static func start() throws -> (JSGlobalContextRef, JSObjectRef, JSObjectRef) {
        if let engine { return engine }

        // Read nt-core.js, or throw if it is missing
        guard let url = bundleURL, let code = try? String(contentsOf: url, encoding: .utf8) else {
            throw Failure(message: "nt-core.js is missing. Run js/build.sh")
        }

        // Make a new JavaScript context and run nt-core.js in it
        guard let context = JSGlobalContextCreate(nil) else { throw Failure(message: "JavaScriptCore didn't start") }
        if let error = evaluate(context, code).error { throw Failure(message: "nt-core.js didn't load. \(error)") }

        // Find NT.call and NT.callKeep and save the engine
        let made = (context, try function(context, "NT.call"), try function(context, "NT.callKeep"))
        engine = made
        return made
    }

    // Find a function in the bundle by name and protect it
    private static func function(_ context: JSGlobalContextRef, _ name: String) throws -> JSObjectRef {
        let found = evaluate(context, name)
        guard found.error == nil, let value = found.value, let object = JSValueToObject(context, value, nil), JSObjectIsFunction(context, object) else {
            throw Failure(message: "nt-core.js has no \(name). Run js/build.sh")
        }
        JSValueProtect(context, object)
        return object
    }

    // Turn a JavaScript value into Swift text, or empty text if there is none
    private static func text(_ context: JSContextRef?, _ value: JSValueRef?) -> String {
        guard let value else { return "" }
        guard let js = JSValueToStringCopy(context, value, nil) else { return "" }
        defer { JSStringRelease(js) }

        // Copy the string's UTF8 bytes out, leaving off the 0 at the end
        let size = JSStringGetMaximumUTF8CStringSize(js)
        var bytes = [CChar](repeating: 0, count: size)
        let written = JSStringGetUTF8CString(js, &bytes, size)
        return String(decoding: bytes.prefix(max(0, written - 1)).map { c in UInt8(bitPattern: c) }, as: UTF8.self)
    }
}


// THE JAVASCRIPT THREAD

// The thread the JavaScript runs on, which runs queued jobs one at a time
private final class JSThread {

    // The lock and signal for the queue, the queued jobs, and the thread
    private let condition = NSCondition()
    private var jobs: [() -> Void] = []
    private var thread: Thread?

    // Start the thread with an 8 MB stack
    func start() {
        let t = Thread { [unowned self] in self.loop() }
        t.name = "NeuroTrace JavaScript"
        t.stackSize = 8 << 20
        thread = t
        t.start()
    }

    // Wait for a job, take it off the queue, run it, and repeat forever
    private func loop() {
        while true {
            condition.lock()
            while jobs.isEmpty { condition.wait() }
            let job = jobs.removeFirst()
            condition.unlock()
            job()
        }
    }

    // Add a job to the queue without waiting for it
    func post(_ job: @escaping () -> Void) {
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    // Run work on the thread and wait for the answer
    func run<R>(_ work: @escaping () throws -> R) -> Result<R, Error> {

        // On the thread itself, just run it
        if let thread, Thread.current == thread { return Result { try work() } }

        // Otherwise queue it and wait until it signals that it is done
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


// VALUES SENT TO THE JAVASCRIPT

// One argument for a JavaScript call, either any Encodable value or a result kept by JSCore.keep
struct JSArg: Encodable {
    private let write: (Encoder) throws -> Void

    // Wrap any Encodable value
    init(_ value: any Encodable) {
        write = { encoder in try value.encode(to: encoder) }
    }

    // An argument that points to a kept result by its ref
    static func kept(_ ref: Int) -> JSArg { JSArg(["__ntRef": ref]) }

    // Write the wrapped value
    func encode(to encoder: Encoder) throws { try write(encoder) }
}

// A drawn point as the JavaScript reads it, with only the time and position
struct JSPoint: Encodable {
    var t: Double
    var x: Double
    var y: Double
}

// Turn a list of samples into JSPoints
extension Array where Element == Sample {
    var forJS: [JSPoint] { map { s in JSPoint(t: s.t, x: s.x, y: s.y) } }
}

// Any JSON value, like a scoring file or a reply from Gemini, passed to the JavaScript as it is
// It keeps true and 1 as different values
indirect enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    // Read a value by trying null, true or false, a number, text, a list, then an object
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    // Write the value as it is
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

    // Turn Foundation's JSON objects, like the dictionaries the tests build, into a JSONValue, or nil if it can't
    static func from(_ raw: Any) -> JSONValue? {
        guard JSONSerialization.isValidJSONObject(raw) || raw is NSNull,
              let data = try? JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
