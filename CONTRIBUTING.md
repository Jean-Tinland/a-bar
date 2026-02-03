# Contributor guidelines

## What do I need to know to help?

If you'd like to help with code contributions, this project is a native macOS application written in Swift. It is developed and built using Xcode. If you don't feel ready to make a code contribution yet, no problem — you can also review or help with documentation or open issues.

If you want to learn more about the technologies we use, check out these resources:

- [The Swift Programming Language](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/)
- [Apple Developer — macOS](https://developer.apple.com/macos/)
- [yabai documentation](https://github.com/asmvik/yabai)

## Coding style conventions

Your PR should:

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Try to follow existing code style and patterns in the codebase
- Include comments for any complex or non-obvious code

## How do I make a contribution?

If you're new to open source contributions, here's a quick rundown tailored for this repository:

1. Find an issue you'd like to work on or propose a new one.
2. Fork the repository to your GitHub account so you have your own copy.
3. Clone your fork locally, for example:
   - `git clone https://github.com/your-username/a-bar.git`

4. Create a branch for your work:
   - `git checkout -b my-feature`

5. Open the project in Xcode (`open a-bar.xcodeproj`) and make your changes.
6. Run the app and any tests locally to verify your changes. You can run tests in Xcode or with `xcodebuild`.
7. Stage and commit your changes with a clear message following [conventional commit](https://www.conventionalcommits.org/en/v1.0.0/) style, for example:
   - `git add .`
   - `git commit -m "feat: short descriptive message"`

8. Push your branch to your fork:
   - `git push origin my-feature`

9. Open a pull request against `Jean-Tinland/a-bar` describing the changes, why they are needed, and any specifics reviewers should know.
10. Address review feedback and update your branch as requested.

## Where can I go for help?

If you need help, open an issue on this repository or use the contact form on [my website](https://www.jeantinland.com/contact/).

## What does the Code of Conduct mean for me?

Our Code of Conduct means that you are responsible for treating everyone on the project with respect and courtesy regardless of their identity. If you experience or witness inappropriate behavior, please follow the reporting instructions in the Code of Conduct so maintainers can respond.

> This contributor guide is adapted from the [opensource.com guide available here](https://opensource.com/life/16/3/contributor-guidelines-template-and-tips).
