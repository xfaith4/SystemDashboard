using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using System;
using System.Collections.Generic;
using System.Diagnostics.Eventing.Reader;
using System.Linq;
using System.Runtime.Versioning;
using System.Threading.Tasks;

namespace EventLogExplorer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class EventLogsController : ControllerBase
    {
        /// <summary>
        /// Represents a summary of a common error event.
        /// </summary>
        public class EventErrorSummary
        {
            public string? LogName { get; set; }
            public string? ProviderName { get; set; }
            public int EventId { get; set; }
            public string? SampleMessage { get; set; } // A sample message for this event type
            public int Count { get; set; }
        }

        /// <summary>
        /// Queries the Application and System event logs for error events,
        /// aggregates them, and returns the most common errors.
        /// </summary>
        /// <param name="topN">The number of top common errors to return. Defaults to 10.</param>
        /// <returns>A list of EventErrorSummary objects.</returns>
        [HttpGet("errors")]
        [SupportedOSPlatform("windows")]
        public async Task<ActionResult<IEnumerable<EventErrorSummary>>> GetCommonErrorEvents([FromQuery] int topN = 10)
        {
            if (!OperatingSystem.IsWindows())
            {
                return StatusCode(StatusCodes.Status501NotImplemented, "Windows Event Log APIs are only supported on Windows.");
            }

            var commonErrors = new Dictionary<(string LogName, string ProviderName, int EventId), (int Count, string SampleMessage)>();
            string[] logNames = { "Application", "System" };

            // XPath query for events with Level=2 (Error)
            // For a complete list of levels, see StandardEventLevel enumeration:
            // Critical=1, Error=2, Warning=3, Informational=4, Verbose=5
            string xPathQuery = "*[System[(Level=2)]]"; 

            foreach (var logName in logNames)
            {
                try
                {
                    var query = new EventLogQuery(logName, PathType.LogName, xPathQuery);
                    using (var reader = new EventLogReader(query))
                    {
                        EventRecord eventRecord;
                        while ((eventRecord = reader.ReadEvent()) != null)
                        {
                            using (eventRecord) // Ensure eventRecord is disposed
                            {
                                string providerName = eventRecord.ProviderName ?? "Unknown";
                                int eventId = eventRecord.Id;
                                string message = eventRecord.FormatDescription() ?? "No description available.";

                                var key = (logName, providerName, eventId);

                                if (commonErrors.TryGetValue(key, out var existingEntry))
                                {
                                    commonErrors[key] = (existingEntry.Count + 1, existingEntry.SampleMessage);
                                }
                                else
                                {
                                    commonErrors[key] = (1, message); // Store the first message as a sample
                                }
                            }
                        }
                    }
                }
                catch (EventLogException ex)
                {
                    // Log the exception, e.g., using a logger
                    Console.WriteLine($"Error reading event log '{logName}': {ex.Message}");
                    // Depending on desired behavior, you might want to throw or return partial data.
                    // For this example, we'll continue to the next log.
                }
                catch (UnauthorizedAccessException ex)
                {
                    Console.WriteLine($"Access denied for event log '{logName}'. Ensure the application has necessary permissions: {ex.Message}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"An unexpected error occurred while processing log '{logName}': {ex.Message}");
                }
            }

            // Order by count descending and take the top N
            var result = commonErrors
                .Select(entry => new EventErrorSummary
                {
                    LogName = entry.Key.LogName,
                    ProviderName = entry.Key.ProviderName,
                    EventId = entry.Key.EventId,
                    SampleMessage = entry.Value.SampleMessage,
                    Count = entry.Value.Count
                })
                .OrderByDescending(s => s.Count)
                .Take(topN)
                .ToList();

            return Ok(result);
        }
    }
}