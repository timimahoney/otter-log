# Otter

A hopefully good log viewer.

## Overview

Otter is a native macOS application designed to make viewing and analyzing log archives from Apple's unified logging system (OSLog) more intuitive and efficient. It provides advanced filtering, colorization, and search capabilities to help developers debug issues faster.

## Features

- **Fast Log Loading**: Efficiently loads and displays log archives (.logarchive files)
- **Advanced Filtering**: Create complex queries to find exactly what you're looking for
  - Filter by subsystem, process, category, and more
  - Compound queries with AND/OR/NOT operators
  - Save frequently used filters for quick access
- **Colorization**: Assign colors to specific log entries based on custom rules
- **Activity Tracking**: View and filter by system activities
- **Statistics View**: Get insights into your logs with detailed statistics
- **Timeline View**: Visualize log density over time

## Getting Started

1. Open Otter
2. Load a log archive using one of these methods:
   - From a sysdiagnose archive
   - Using `log collect` command: `sudo log collect --output myarchive.logarchive`
   - From Xcode device logs

## Building from Source

1. Clone the repository
2. Open `Otter/Otter.xcodeproj` in Xcode
3. Build and run

## Open Source

Since you're reading this, you already know this is an open source project. Beware, there is some terrible code in here. That said, some of it might be useful.

## Contributing

Contributions are welcome! Here are some ideas for improvements:

- **Format Support**: Add support for loading plaintext log files
- **Export Options**: Additional export formats (CSV, JSON, etc.)
- **Performance**: Optimize loading and filtering for very large archives
- **UI Enhancements**: Your wildest dreams can come true
- **Search**: Regular expression support in filters
- **Visualizations**: New ways to visualize log data
- **Cleanup**: Just make this thing generally better and cleaner

Please feel free to submit pull requests or open issues for bugs and feature requests.

## License

I honestly don't even know. The code is here and it's not my fault if it hurts you.