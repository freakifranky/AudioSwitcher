# Audio Switcher

A macOS menu bar utility to quickly switch default input and output audio devices.

## Features
- Switch output devices
- Switch input devices
- Quick presets
- Output volume control when supported
- Input level control when supported
- Menu bar popover UI

## Notes
Some audio devices do not expose software volume or input gain control to macOS, so those sliders may appear unavailable.

## Run
Open the Xcode project and run the app.

## Setup
For menu bar only behavior, set `Application is agent (UIElement)` to `YES` in `Info.plist`.
