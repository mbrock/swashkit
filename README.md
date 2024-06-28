# SwashKit

SwashKit is a lightweight audio recording and encoding library built with Zig.
It provides a simple interface for capturing audio from microphones and encoding
it using the Opus codec.

It's not ready for anything, but it seems to work.

## Features

- Microphone device enumeration
- Audio capture using miniaudio
- Very low-latency containerless Opus encoding
- Cross-platform
- XCFramework generation for easy integration with iOS/macOS projects
- MIT license

## Building

To build SwashKit, you'll need Zig 0.13 installed. Then run:

```sh
zig build
zig build xcframework # for the Mac universal Xcode framework
```

## API

SwashKit provides a simple C API for audio recording and Opus encoding. The main
functions are:

- `mic_init`: Initialize the audio context
- `mic_free`: Free the audio context
- `mic_scan`: Scan for available audio devices
- `mic_play`: Start recording from a selected device
- `mic_stop`: Stop recording
- `mic_buf`: Get the encoded audio buffer
- `mic_dev`: Get device information

## Using from Swift

Build the framework and add it to your XCode project.

```swift
import Foundation
import SwashKit
import Combine

func micServiceCallback(context: OpaquePointer?) {
    guard let context = context else {
        return
    }

    let arg = mic_arg(context)

    let it = Unmanaged<MicService>.fromOpaque(arg!).takeUnretainedValue()
    var buf: UnsafePointer<UInt8>?
    var len: Int32 = 0

    mic_buf(it.ctx, &buf, &len)
    it.data.send(Data(bytes: buf!, count: Int(len)))
}

class MicService {
    var ctx: OpaquePointer? = nil
    var dev: Int32?

    let data: PassthroughSubject<Data, Error> = PassthroughSubject()

    init() {
        let this = Unmanaged.toOpaque(Unmanaged.passRetained(self))()

        self.ctx = mic_init(micServiceCallback, this)
        let len = mic_scan(self.ctx)

        for i in 0..<len {
            var buf: UnsafePointer<CChar>?
            var isDefault: Int32 = 0

            mic_dev(self.ctx, i, &buf, &isDefault)

            if isDefault != 0 {
                dev = i
                break
            }
        }
    }

    func start() {
        mic_play(ctx, dev!)
    }
}
```
