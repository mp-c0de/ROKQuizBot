# ROK Quiz Bot (Beta)

A macOS application for automatically answering Rise of Kingdoms quiz questions using OCR and a question database.

Made by mpcode

## Features

- **Instant Hotkey Trigger**: Press `⌘⌃0` to capture, find answer, and click - all in one instant action
- **Screen Area Selection**: Click and drag to select the screen region containing the quiz
- **OCR Text Recognition**: Uses Apple's Vision framework for fast text recognition
- **Fast Question Matching**: O(1) dictionary lookup with 837+ built-in questions
- **Auto-Click Answers**: Automatically clicks on the correct answer location
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

2. **Answer Questions**: Press `⌘⌃0` (Command + Control + 0) when you see a question - the app will instantly capture, find the answer, and click it

3. **Settings**:
   - **Hide Cursor**: Hide cursor during capture to avoid blocking text
   - **Sound Effects**: Play sound when answering a question
   - **Auto-add Unknown**: Automatically save unrecognised questions

4. **Manage Questions**:
   - View and search the question database
   - Review and resolve unknown questions

5. **AI Settings** (Optional):
   - Configure Claude or ChatGPT API keys
   - Use AI to help answer unknown questions

## Question Database

The app includes 837 built-in Rise of Kingdoms quiz questions embedded directly in the code for instant O(1) lookup.

User-added questions are saved separately to `~/Documents/ROKQuizBot/user_questions.json`.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘⌃0` | Capture and answer (Command + Control + 0) |

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
