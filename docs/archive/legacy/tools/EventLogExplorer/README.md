## Project Summary: Event Log Explorer

This report outlines the structure, functionality, and deployment of the "Event Log Explorer" application, a portable web application designed to query local Windows Event Logs for common errors and visualize them.

### 1. Project Structure

The application follows a client-server model implemented using ASP.NET Core:

*   **Backend:** An ASP.NET Core Web API (C#) serves as the backend, responsible for accessing and processing Windows Event Log data. It exposes RESTful endpoints for the frontend.
*   **Frontend:** A single-page application built using ASP.NET Core Razor Pages (HTML, CSS, JavaScript) consumes data from the backend API.
*   **Hosting:** The application is self-contained, leveraging Kestrel for hosting, allowing for portable deployment across Windows machines.

The project directory structure is as follows:

```
EventLogExplorer/
├── EventLogExplorer.csproj
├── Program.cs
├── Controllers/
│   └── EventLogsController.cs
├── Pages/
│   ├── _ViewImports.cshtml
│   ├── _ViewStart.cshtml
│   └── Index.cshtml
└── wwwroot/
    ├── css/
    │   └── site.css
    └── js/
        └── site.js
```

### 2. C# Code Interaction with Windows Event Log

The backend functionality resides within the `EventLogsController.cs`.

*   **Event Log Access:** The `System.Diagnostics.Eventing.Reader` namespace is utilized for robust querying of modern Windows Event Logs. Specifically, `EventLogQuery` is used to define the query criteria, and `EventLogReader` is used to read events.
*   **Querying Errors:** The `GetCommonErrorEvents` endpoint targets "Application" and "System" event logs. It employs an XPath query `*[System[(Level=2)]]` to filter for events with a level of "Error".
*   **Data Aggregation:** As events are read, the C# code aggregates them by `LogName`, `ProviderName`, and `EventId`. It maintains a count for each unique error type and stores a `SampleMessage`.
*   **Error Handling:** The code includes `try-catch` blocks to handle potential `EventLogException` (e.g., if a log is inaccessible) and `UnauthorizedAccessException`, providing console output for debugging.
*   **Output:** The aggregated data is transformed into a list of `EventErrorSummary` objects, which are then ordered by count descending and returned as JSON.

### 3. Frontend Data Visualization

The frontend is implemented as an ASP.NET Core Razor Page (`Index.cshtml`) with client-side scripting.

*   **HTML Structure (`Index.cshtml`):** Provides the basic layout using Bootstrap 5 for responsive design. It includes `canvas` elements for the charts and a `table` to display raw event data.
*   **Styling (`site.css`):** Custom CSS provides minor aesthetic adjustments to the Bootstrap theme.
*   **JavaScript (`site.js`):
    *   **Data Fetching:** Upon page load, `DOMContentLoaded` triggers `fetchEventData()`, which makes an asynchronous call to the backend API (`/api/EventLogs/errors`).
    *   **Table Display:** `displayEventTable()` populates the HTML table with the raw event data received from the API.
    *   **Histograms (Chart.js):**
        *   `renderEventIdChart()` aggregates event counts by `EventId` and renders a horizontal bar chart using Chart.js.
        *   `renderProviderChart()` aggregates event counts by `ProviderName` and renders another horizontal bar chart using Chart.js.
    *   **Libraries:** Bootstrap JS and Chart.js are loaded from CDNs to provide functionality.

### 4. How to Build and Run the Portable Application

The application is configured for a single-file, self-contained, portable executable deployment, meaning it does not require the .NET runtime to be pre-installed on the target Windows machine.

**Prerequisites:**
*   .NET 8.0 SDK installed on your development machine.

**Build and Publish Instructions:**

1.  **Navigate to Project Directory:** Open your terminal (e.g., Command Prompt, PowerShell, Git Bash) and navigate to the `EventLogExplorer` project root directory (where `EventLogExplorer.csproj` is located).
    ```bash
    cd path/to/EventLogExplorer
    ```

2.  **Publish the Application:** Execute the following command to build and publish the application as a single, self-contained executable for Windows x64.
    ```bash
    dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=true -o ./publish
    ```
    *   `-c Release`: Specifies a Release build configuration for optimized performance.
    *   `-r win-x64`: Targets Windows 64-bit runtime, making it executable on Windows x64 machines.
    *   `--self-contained true`: Ensures all necessary runtime components are bundled with the application.
    *   `-p:PublishSingleFile=true`: Creates a single executable file.
    *   `-p:PublishTrimmed=true`: Trims unused framework parts to reduce file size.
    *   `-o ./publish`: Specifies the output directory for the published files.

3.  **Run the Application:**
    *   After successful publishing, navigate to the newly created `publish` directory:
        ```bash
        cd publish
        ```
    *   Locate the executable file (e.g., `EventLogExplorer.exe`) and run it from the terminal or by double-clicking it in File Explorer.
        ```bash
        .\EventLogExplorer.exe
        ```
    *   The application will start, open a console window showing server startup messages, and typically launch a web browser to the application's URL (e.g., `https://localhost:5001` or `http://localhost:5000`). If it doesn't automatically open, check the console output for the listening URLs and navigate to one manually.
