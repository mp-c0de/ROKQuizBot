# ROK Quiz Bot (Beta)

A macOS application for automatically answering Rise of Kingdoms quiz questions using OCR and a question database.

Made by mpcode

## Features

- **Instant Hotkey Trigger**: Press `0` to capture, find answer, and click - all in one instant action
- **Screen Area Selection**: Click and drag to select the screen region containing the quiz
- **Visual Capture Border**: Optional red border overlay shows the capture area on screen
- **Quiz Layout Configuration**: Define precise zones for question and answer areas - supports multiple games with named layouts (capture area saved per layout)
- **OCR Text Recognition**: Uses Apple's Vision framework with tuneable preprocessing settings
- **Capture Quality Selection**: Choose between Low, Medium, or Best (Retina) quality for optimal OCR
- **Fast Question Matching**: O(1) dictionary lookup with 837+ built-in questions
- **Auto-Click Answers**: Automatically clicks on the correct answer location with cursor move-away to prevent double-clicks
- **Unknown Questions**: Captures unrecognised questions for manual answer input
- **AI Integration**: Optional AI (Claude/ChatGPT) integration for answering unknown questions

## Requirements

- macOS 15.0 or later
- Xcode 26 (for building from source)
- Screen Recording permission
- Accessibility permission (for mouse control and global hotkey)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/mp-c0de/ROKQuizBot.git
   ```

2. Open `ROKQuizBot.xcodeproj` in Xcode

3. Build and run the application

4. Grant the required permissions when prompted:
   - **Screen Recording**: Required to capture the quiz area
   - **Accessibility**: Required for automated mouse clicking and global hotkey

## Usage

1. **Select Capture Area**: Click "Select Capture Area" and drag to select the region where quiz questions appear

2. **Configure Quiz Layout** (Recommended): Click "Configure Quiz Layout" to define precise zones:
   - Enter a **layout name** at the top (required)
   - Press **Q** to add a Question zone
   - Press **A/B/C/D** to add Answer zones
   - Drag zones to move, drag handles to resize
   - Press **Enter** to save (also works from the name field), **ESC** to cancel
   - Each layout saves its own capture area - switch layouts to restore different capture regions

3. **Answer Questions**: Press `0` when you see a question - the app will instantly capture, find the answer, and click it

4. **Settings**:
   - **Auto-Click Answer**: Automatically click the answer when found (disable to just view the answer)
   - **Hide Cursor**: Hide cursor during capture to avoid blocking text
   - **Sound Effects**: Play sound when answering a question
   - **Auto-add Unknown**: Automatically save unrecognised questions
   - **Show Capture Area Border**: Display a red border overlay on screen showing the capture area

5. **Capture Quality**: Select image quality for screen capture:
   - **Low (0.5x)**: Faster, smaller images
   - **Medium (1.0x)**: Balanced quality
   - **Best (2.0x Retina)**: Highest quality for difficult text

6. **OCR Settings**: Tune image preprocessing to improve text recognition:
   - **Presets**: Default, Game Text (high contrast), Light on Dark
   - **Fine Tuning**: Adjust contrast, brightness, scale factor
   - **Options**: Grayscale, sharpening, colour inversion
   - Use "Game Text" preset for stylised game text with low contrast

7. **Manage Questions**:
   - View and search the question database
   - Review and resolve unknown questions

8. **AI Settings** (Optional):
   - Configure Claude or ChatGPT API keys
   - Test API connection with built-in test buttons
   - Use AI to help answer unknown questions

## Data Storage

The app includes 837 built-in Rise of Kingdoms quiz questions embedded directly in the code for instant O(1) lookup.

| Data | Location |
|------|----------|
| User-added questions | `~/Documents/ROKQuizBot/user_questions.json` |
| Quiz layouts (incl. capture areas) | `~/Documents/ROKQuizBot/quiz_layouts.json` |
| App settings | UserDefaults (persistent across app restarts) |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `0` | Capture and answer |
| `Cmd+Shift+Esc` | Emergency stop |

### Layout Configuration Window

| Key | Action |
|-----|--------|
| `Q` | Add/replace Question zone |
| `A/B/C/D` | Add/replace Answer zone |
| `Delete` | Remove selected zone |
| `Enter` | Save layout |
| `ESC` | Cancel |

## Privacy

- All processing is done locally on your Mac
- No data is sent to external servers unless you configure AI integration
- AI integration (optional) sends screenshots to the configured AI provider

## Development

- **main** branch: Protected, stable releases only
- **develop** branch: Active development

## Licence

This project is for personal use only.

## Disclaimer

This tool is for educational purposes. Use responsibly and in accordance with the game's terms of service.
