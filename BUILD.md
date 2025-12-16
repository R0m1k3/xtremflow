# How to Build XtremFlow as an Executable

To create a standalone `.exe` version of XtremFlow, you need to build it on your machine.

## Prerequisites

Since you are currently using Docker, you likely don't have these installed on your Windows system yet. You must install them to build the Windows executable.

1.  **Install Flutter SDK**
    *   Download from: [flutter.dev/install/windows](https://docs.flutter.dev/get-started/install/windows)
    *   Extract the zip file to `C:\src\flutter` (for example).
    *   Add `flutter/bin` to your **System PATH**.

2.  **Verify Installation**
    *   Open a new terminal.
    *   Run `flutter doctor`.
    *   Ensure it says "Flutter ... channel stable".

## Building the App

Once Flutter is installed:

1.  Open PowerShell in this folder.
2.  Run the build script:
    ```powershell
    .\build_release.ps1
    ```

## Adding FFmpeg

1.  After the build finishes, open the new `dist` folder.
2.  Go to `dist/ffmpeg/bin`.
3.  Download `ffmpeg.exe` (from [ffmpeg.org](https://ffmpeg.org/download.html)) and place it there.

## Running

Double-click `dist/start.bat` to run the server!
