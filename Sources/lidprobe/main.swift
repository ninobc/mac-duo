import Foundation
import LidAngle

/// Prints the hinge angle. `lidprobe` streams; `lidprobe once` prints one line.
let sensor = LidAngleSensor()
guard sensor.isAvailable, let resolution = sensor.resolution else {
    FileHandle.standardError.write(Data("No lid angle sensor found on this Mac.\n".utf8))
    exit(1)
}
let mode = CommandLine.arguments.dropFirst().first ?? "stream"
print("sensor: report resolution \(resolution.label)")
if mode == "once" {
    if let angle = sensor.read() { print(String(format: "%.2f", angle)) }
    exit(0)
}
var last = -1.0
while true {
    if let angle = sensor.read(), angle != last {
        last = angle
        print(String(format: "%@ %7.2f°", ISO8601DateFormatter().string(from: Date()), angle))
        fflush(stdout)
    }
    usleep(20_000)
}
