
# Center on the origin, then scale to unit RMS radius
def normalize(x, y):
    x = x - np.mean(x)
    y = y - np.mean(y)
    scale = np.sqrt(np.mean(x**2 + y**2))
    return x / scale, y / scale