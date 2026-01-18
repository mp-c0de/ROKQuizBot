# ROK Quiz Bot

A macOS application for automatically answering Rise of Kingdoms quiz questions using OCR and a question database.

Made by mpcode

## Features

- **Screen Area Selection**: Click and drag to select the screen region containing the quiz
- **OCR Text Recognition**: Uses Apple's Vision framework for accurate text recognition
- **Question Matching**: Fuzzy matching algorithm to find questions even with OCR errors
- **Auto-Click Answers**: Automatically clicks on the correct answer location
- **Question Database**: Pre-loaded with 300+ Rise of Kingdoms quiz questions
- **Unknown Questions**: Captures unrecognised questions for manual answer input
- **AI Integration**: Optional AI (Claude/ChatGPT) integration for answering unknown questions
- **Emergency Stop**: Press `⌘⇧Esc` to immediately stop the bot

## Requirements

- macOS 15.0 or later
- Xcode 26 (for building from source)
- Screen Recording permission
- Accessibility permission (for mouse control)

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/mp-c0de/ROKQuizBot.git
   ```

2. Open `ROKQuizBot.xcodeproj` in Xcode

3. Build and run the application

4. Grant the required permissions when prompted:
   - **Screen Recording**: Required to capture the quiz area
   - **Accessibility**: Required for automated mouse clicking

## Usage

1. **Select Capture Area**: Click "Select Capture Area" and drag to select the region where quiz questions appear

2. **Start Monitoring**: Click "Start" to begin monitoring the selected area

3. **Adjust Settings**:
   - **Interval**: Time between captures (default: 2 seconds)
   - **Hide Cursor**: Hide cursor during capture to avoid blocking text
   - **Sound Effects**: Play sound when answering a question
   - **Auto-add Unknown**: Automatically save unrecognised questions

4. **Manage Questions**:
   - View and search the question database
   - Add new questions manually
   - Review and resolve unknown questions

5. **AI Settings** (Optional):
   - Configure Claude or ChatGPT API keys
   - Use AI to automatically answer unknown questions

## Question Database

The app includes a pre-loaded database of Rise of Kingdoms quiz questions in `questions.json`. Questions are stored in the format:

```json
{
  "text": "What is the tallest peak in the world?",
  "answer": "Mount Everest"
}
```

New questions are saved to `~/Documents/ROKQuizBot/questions.json`.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Start/Stop monitoring |
| `⌘⇧Esc` | Emergency stop |

## Privacy

- All processing is done locally on your Mac
- No data is sent to external servers unless you configure AI integration
- AI integration (optional) sends screenshots to the configured AI provider

## Licence

This project is for personal use only.

## Disclaimer

This tool is for educational purposes. Use responsibly and in accordance with the game's terms of service.
