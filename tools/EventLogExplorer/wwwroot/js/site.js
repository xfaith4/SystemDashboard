document.addEventListener('DOMContentLoaded', () => {
    fetchEventData();
});

async function fetchEventData() {
    try {
        // Adjust the topN parameter as needed, e.g., to get more data for charts
        const response = await fetch('/api/EventLogs/errors?topN=20');
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        const eventData = await response.json();
        console.log("Fetched event data:", eventData);
        displayEventTable(eventData);
        renderEventIdChart(eventData);
        renderProviderChart(eventData);

    } catch (error) {
        console.error("Error fetching event log data:", error);
        document.getElementById('eventDataTable').innerHTML = `<tr><td colspan="5" class="text-danger">Failed to load data: ${error.message}</td></tr>`;
    }
}

function displayEventTable(data) {
    const tableBody = document.getElementById('eventDataTable');
    tableBody.innerHTML = ''; // Clear existing data

    if (data.length === 0) {
        tableBody.innerHTML = '<tr><td colspan="5" class="text-muted text-center">No common error events found.</td></tr>';
        return;
    }

    data.forEach(event => {
        const row = tableBody.insertRow();
        row.insertCell().textContent = event.count;
        row.insertCell().textContent = event.logName;
        row.insertCell().textContent = event.providerName;
        row.insertCell().textContent = event.eventId;
        row.insertCell().textContent = event.sampleMessage;
    });
}

function renderEventIdChart(data) {
    const ctx = document.getElementById('eventIdChart').getContext('2d');

    // Aggregate counts for each Event ID
    const eventIdCounts = data.reduce((acc, event) => {
        acc[event.eventId] = (acc[event.eventId] || 0) + event.count;
        return acc;
    }, {});

    const labels = Object.keys(eventIdCounts).sort((a, b) => eventIdCounts[b] - eventIdCounts[a]); // Sort by count descending
    const counts = labels.map(id => eventIdCounts[id]);

    new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'Occurrences by Event ID',
                data: counts,
                backgroundColor: 'rgba(54, 162, 235, 0.6)', // Blue
                borderColor: 'rgba(54, 162, 235, 1)',
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: 'y', // Make it a horizontal bar chart
            scales: {
                x: {
                    beginAtZero: true,
                    title: {
                        display: true,
                        text: 'Count'
                    }
                },
                y: {
                    title: {
                        display: true,
                        text: 'Event ID'
                    },
                    ticks: {
                        autoSkip: false // Show all labels if space allows
                    }
                }
            },
            plugins: {
                legend: {
                    display: true
                },
                title: {
                    display: false
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            return `Count: ${context.parsed.x}`;
                        }
                    }
                }
            }
        }
    });
}

function renderProviderChart(data) {
    const ctx = document.getElementById('providerChart').getContext('2d');

    // Aggregate counts for each Provider Name
    const providerCounts = data.reduce((acc, event) => {
        acc[event.providerName] = (acc[event.providerName] || 0) + event.count;
        return acc;
    }, {});

    const labels = Object.keys(providerCounts).sort((a, b) => providerCounts[b] - providerCounts[a]); // Sort by count descending
    const counts = labels.map(provider => providerCounts[provider]);

    new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'Occurrences by Provider',
                data: counts,
                backgroundColor: 'rgba(75, 192, 192, 0.6)', // Greenish-blue
                borderColor: 'rgba(75, 192, 192, 1)',
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: 'y', // Make it a horizontal bar chart
            scales: {
                x: {
                    beginAtZero: true,
                    title: {
                        display: true,
                        text: 'Count'
                    }
                },
                y: {
                    title: {
                        display: true,
                        text: 'Provider Name'
                    },
                    ticks: {
                        autoSkip: false // Show all labels if space allows
                    }
                }
            },
            plugins: {
                legend: {
                    display: true
                },
                title: {
                    display: false
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            return `Count: ${context.parsed.x}`;
                        }
                    }
                }
            }
        }
    });
}