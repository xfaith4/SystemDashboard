// Table Enhancements: CSV Export, Column Sorting, and Data Refresh

/**
 * TableExport - CSV export functionality for tables
 */
const TableExport = {
  /**
   * Export table data to CSV
   */
  exportToCSV(table, filename = 'export.csv') {
    if (typeof table === 'string') {
      table = document.querySelector(table);
    }
    
    if (!table) {
      console.error('Table not found');
      return;
    }

    const rows = [];
    
    // Get headers
    const headers = Array.from(table.querySelectorAll('thead th'))
      .map(th => this.cleanText(th.textContent));
    rows.push(headers);
    
    // Get data rows
    const dataRows = table.querySelectorAll('tbody tr');
    dataRows.forEach(tr => {
      const cells = Array.from(tr.querySelectorAll('td'))
        .map(td => this.cleanText(td.textContent));
      if (cells.length > 0 && !tr.classList.contains('empty-state') && !tr.classList.contains('loading')) {
        rows.push(cells);
      }
    });
    
    // Convert to CSV
    const csv = rows.map(row => 
      row.map(cell => this.escapeCSV(cell)).join(',')
    ).join('\n');
    
    // Download
    this.downloadCSV(csv, filename);
    
    // Show success message
    if (window.Toast) {
      Toast.success(`Exported ${dataRows.length} rows to ${filename}`, 'Export Complete');
    }
  },

  /**
   * Clean text content
   */
  cleanText(text) {
    return text.trim().replace(/\s+/g, ' ');
  },

  /**
   * Escape CSV field
   */
  escapeCSV(field) {
    // If field contains comma, quote, or newline, wrap in quotes and escape quotes
    if (field.includes(',') || field.includes('"') || field.includes('\n')) {
      return `"${field.replace(/"/g, '""')}"`;
    }
    return field;
  },

  /**
   * Download CSV file
   */
  downloadCSV(csv, filename) {
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    
    link.setAttribute('href', url);
    link.setAttribute('download', filename);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    
    // Clean up
    setTimeout(() => URL.revokeObjectURL(url), 100);
  },

  /**
   * Add export button to a table
   */
  addExportButton(table, options = {}) {
    if (typeof table === 'string') {
      table = document.querySelector(table);
    }
    
    if (!table) return;

    const {
      filename = 'table-export.csv',
      buttonText = 'Export CSV',
      buttonClass = 'btn-secondary',
      container = null
    } = options;

    const button = document.createElement('button');
    button.className = buttonClass;
    button.innerHTML = `
      <svg style="width: 1rem; height: 1rem; margin-right: 0.5rem;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/>
        <polyline points="7 10 12 15 17 10"/>
        <line x1="12" y1="15" x2="12" y2="3"/>
      </svg>
      ${buttonText}
    `;
    
    button.onclick = () => this.exportToCSV(table, filename);
    
    if (container) {
      const containerEl = typeof container === 'string' ? document.querySelector(container) : container;
      if (containerEl) {
        containerEl.appendChild(button);
      }
    } else {
      // Insert before table
      table.parentNode.insertBefore(button, table);
    }
    
    return button;
  }
};

/**
 * DataRefreshIndicator - Visual indicators for data freshness
 */
const DataRefreshIndicator = {
  indicators: new Map(),

  /**
   * Create a refresh indicator
   */
  create(options) {
    const {
      id,
      container,
      autoRefresh = false,
      refreshInterval = 30000, // 30 seconds
      onRefresh,
      showLastUpdate = true
    } = options;

    const indicatorId = id || `refresh-${Date.now()}`;
    
    // Create indicator element
    const indicator = document.createElement('div');
    indicator.className = 'data-refresh-indicator';
    indicator.id = `indicator-${indicatorId}`;
    
    indicator.innerHTML = `
      <div class="refresh-status">
        <span class="refresh-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="23 4 23 10 17 10"/>
            <polyline points="1 20 1 14 7 14"/>
            <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
          </svg>
        </span>
        ${showLastUpdate ? `<span class="refresh-text">Updated <span class="refresh-time">just now</span></span>` : ''}
        <button class="refresh-button" aria-label="Refresh data">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="23 4 23 10 17 10"/>
            <polyline points="1 20 1 14 7 14"/>
            <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
          </svg>
        </button>
      </div>
    `;

    // Add to container
    const containerEl = typeof container === 'string' ? document.querySelector(container) : container;
    if (containerEl) {
      containerEl.appendChild(indicator);
    }

    // Set up refresh button
    const refreshBtn = indicator.querySelector('.refresh-button');
    refreshBtn.onclick = () => this.refresh(indicatorId);

    // Store instance
    const instance = {
      id: indicatorId,
      element: indicator,
      lastUpdate: Date.now(),
      refreshing: false,
      autoRefresh,
      refreshInterval,
      onRefresh,
      timer: null
    };
    
    this.indicators.set(indicatorId, instance);

    // Start auto-refresh if enabled
    if (autoRefresh) {
      this.startAutoRefresh(indicatorId);
    }

    // Update time display
    if (showLastUpdate) {
      this.startTimeUpdater(indicatorId);
    }

    return indicatorId;
  },

  /**
   * Refresh data
   */
  async refresh(id) {
    const instance = this.indicators.get(id);
    if (!instance || instance.refreshing) return;

    instance.refreshing = true;
    instance.element.classList.add('refreshing');

    try {
      if (instance.onRefresh) {
        await instance.onRefresh();
      }
      
      instance.lastUpdate = Date.now();
      
      if (window.Toast) {
        Toast.success('Data refreshed successfully', 'Refreshed');
      }
    } catch (error) {
      console.error('Refresh failed:', error);
      if (window.Toast) {
        Toast.error('Failed to refresh data', 'Error');
      }
    } finally {
      instance.refreshing = false;
      instance.element.classList.remove('refreshing');
    }
  },

  /**
   * Start auto-refresh timer
   */
  startAutoRefresh(id) {
    const instance = this.indicators.get(id);
    if (!instance) return;

    this.stopAutoRefresh(id); // Clear existing timer

    instance.timer = setInterval(() => {
      this.refresh(id);
    }, instance.refreshInterval);
  },

  /**
   * Stop auto-refresh timer
   */
  stopAutoRefresh(id) {
    const instance = this.indicators.get(id);
    if (!instance || !instance.timer) return;

    clearInterval(instance.timer);
    instance.timer = null;
  },

  /**
   * Start time updater
   */
  startTimeUpdater(id) {
    const instance = this.indicators.get(id);
    if (!instance) return;

    const updateTime = () => {
      const timeEl = instance.element.querySelector('.refresh-time');
      if (timeEl) {
        const elapsed = Date.now() - instance.lastUpdate;
        timeEl.textContent = this.formatElapsed(elapsed);
      }
    };

    // Update immediately
    updateTime();

    // Update every 10 seconds
    setInterval(updateTime, 10000);
  },

  /**
   * Format elapsed time
   */
  formatElapsed(ms) {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (seconds < 10) return 'just now';
    if (seconds < 60) return `${seconds}s ago`;
    if (minutes < 60) return `${minutes}m ago`;
    if (hours < 24) return `${hours}h ago`;
    return `${days}d ago`;
  },

  /**
   * Destroy indicator
   */
  destroy(id) {
    const instance = this.indicators.get(id);
    if (!instance) return;

    this.stopAutoRefresh(id);
    instance.element.remove();
    this.indicators.delete(id);
  }
};

/**
 * TableSorting - Client-side table sorting
 */
const TableSorting = {
  /**
   * Make table sortable
   */
  makeSortable(table, options = {}) {
    if (typeof table === 'string') {
      table = document.querySelector(table);
    }
    
    if (!table) return;

    const {
      sortableColumns = null, // null = all columns sortable
      onSort = null
    } = options;

    const headers = table.querySelectorAll('thead th');
    
    headers.forEach((header, index) => {
      // Skip if not sortable
      if (sortableColumns && !sortableColumns.includes(index)) {
        return;
      }

      header.classList.add('sortable');
      header.setAttribute('data-column', index);
      header.style.cursor = 'pointer';
      
      // Add sort icon
      const sortIcon = document.createElement('span');
      sortIcon.className = 'sort-icon';
      sortIcon.innerHTML = `
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M12 5v14M19 12l-7 7-7-7"/>
        </svg>
      `;
      header.appendChild(sortIcon);

      // Add click handler
      header.onclick = () => {
        this.sortTable(table, index, onSort);
      };
    });
  },

  /**
   * Sort table by column
   */
  sortTable(table, columnIndex, onSort) {
    const tbody = table.querySelector('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    const headers = table.querySelectorAll('thead th');
    const header = headers[columnIndex];
    
    // Determine sort direction
    const currentSort = header.getAttribute('data-sort');
    const direction = currentSort === 'asc' ? 'desc' : 'asc';
    
    // Clear all sort indicators
    headers.forEach(h => {
      h.removeAttribute('data-sort');
      h.classList.remove('sorted-asc', 'sorted-desc');
    });
    
    // Set new sort
    header.setAttribute('data-sort', direction);
    header.classList.add(`sorted-${direction}`);
    
    // Sort rows
    rows.sort((a, b) => {
      const aCell = a.querySelectorAll('td')[columnIndex];
      const bCell = b.querySelectorAll('td')[columnIndex];
      
      if (!aCell || !bCell) return 0;
      
      const aValue = this.getCellValue(aCell);
      const bValue = this.getCellValue(bCell);
      
      let comparison = 0;
      if (typeof aValue === 'number' && typeof bValue === 'number') {
        comparison = aValue - bValue;
      } else {
        comparison = String(aValue).localeCompare(String(bValue));
      }
      
      return direction === 'asc' ? comparison : -comparison;
    });
    
    // Reorder rows
    rows.forEach(row => tbody.appendChild(row));
    
    // Call callback
    if (onSort) {
      onSort(columnIndex, direction);
    }
  },

  /**
   * Get cell value for sorting
   */
  getCellValue(cell) {
    // Check for data-sort-value attribute
    if (cell.hasAttribute('data-sort-value')) {
      const val = cell.getAttribute('data-sort-value');
      const num = parseFloat(val);
      return isNaN(num) ? val : num;
    }
    
    // Get text content
    const text = cell.textContent.trim();
    
    // Try to parse as number
    const num = parseFloat(text.replace(/[^0-9.-]/g, ''));
    if (!isNaN(num)) {
      return num;
    }
    
    // Try to parse as date
    const date = Date.parse(text);
    if (!isNaN(date)) {
      return date;
    }
    
    return text;
  }
};

// Make utilities available globally
window.TableExport = TableExport;
window.DataRefreshIndicator = DataRefreshIndicator;
window.TableSorting = TableSorting;
