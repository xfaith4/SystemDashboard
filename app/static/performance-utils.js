/**
 * Frontend Performance Utilities
 * 
 * Provides utilities for improving frontend performance:
 * - Debounce and throttle functions for event handlers
 * - Lazy loading for charts and images
 * - Intersection observer utilities
 */

/**
 * Debounce function execution - waits until calls stop before executing
 * Perfect for search inputs, resize handlers, etc.
 * 
 * @param {Function} func - Function to debounce
 * @param {number} delay - Delay in milliseconds
 * @returns {Function} Debounced function
 * 
 * @example
 * const debouncedSearch = debounce((query) => {
 *     fetchResults(query);
 * }, 300);
 * 
 * searchInput.addEventListener('input', (e) => {
 *     debouncedSearch(e.target.value);
 * });
 */
function debounce(func, delay = 300) {
    let timeoutId = null;
    
    return function debounced(...args) {
        const context = this;
        
        // Clear previous timeout
        if (timeoutId !== null) {
            clearTimeout(timeoutId);
        }
        
        // Set new timeout
        timeoutId = setTimeout(() => {
            func.apply(context, args);
            timeoutId = null;
        }, delay);
    };
}

/**
 * Throttle function execution - limits how often function can be called
 * Perfect for scroll handlers, mousemove, etc.
 * 
 * @param {Function} func - Function to throttle
 * @param {number} limit - Minimum time between calls in milliseconds
 * @returns {Function} Throttled function
 * 
 * @example
 * const throttledScroll = throttle(() => {
 *     updateScrollPosition();
 * }, 100);
 * 
 * window.addEventListener('scroll', throttledScroll);
 */
function throttle(func, limit = 100) {
    let inThrottle = false;
    let lastResult;
    
    return function throttled(...args) {
        const context = this;
        
        if (!inThrottle) {
            lastResult = func.apply(context, args);
            inThrottle = true;
            
            setTimeout(() => {
                inThrottle = false;
            }, limit);
        }
        
        return lastResult;
    };
}

/**
 * Lazy loader for charts and heavy content using Intersection Observer
 */
class LazyLoader {
    /**
     * Initialize lazy loader
     * 
     * @param {Object} options - Configuration options
     * @param {number} options.rootMargin - Margin around viewport (default: '50px')
     * @param {number} options.threshold - Visibility threshold 0-1 (default: 0.1)
     */
    constructor(options = {}) {
        this.rootMargin = options.rootMargin || '50px';
        this.threshold = options.threshold || 0.1;
        this.loadingCallbacks = new Map();
        
        // Check if IntersectionObserver is supported
        if (!('IntersectionObserver' in window)) {
            console.warn('IntersectionObserver not supported, lazy loading disabled');
            this.observer = null;
            return;
        }
        
        this.observer = new IntersectionObserver(
            (entries) => this._handleIntersection(entries),
            {
                rootMargin: this.rootMargin,
                threshold: this.threshold
            }
        );
    }
    
    /**
     * Register an element for lazy loading
     * 
     * @param {HTMLElement} element - Element to observe
     * @param {Function} loadCallback - Function to call when element is visible
     * 
     * @example
     * const loader = new LazyLoader();
     * const chartContainer = document.getElementById('chart');
     * 
     * loader.observe(chartContainer, () => {
     *     renderChart(chartContainer);
     * });
     */
    observe(element, loadCallback) {
        if (!this.observer) {
            // Fallback: load immediately if IntersectionObserver not supported
            loadCallback();
            return;
        }
        
        // Store callback
        this.loadingCallbacks.set(element, loadCallback);
        
        // Start observing
        this.observer.observe(element);
    }
    
    /**
     * Stop observing an element
     * 
     * @param {HTMLElement} element - Element to stop observing
     */
    unobserve(element) {
        if (this.observer) {
            this.observer.unobserve(element);
        }
        this.loadingCallbacks.delete(element);
    }
    
    /**
     * Disconnect observer and clear all callbacks
     */
    disconnect() {
        if (this.observer) {
            this.observer.disconnect();
        }
        this.loadingCallbacks.clear();
    }
    
    /**
     * Handle intersection events
     * @private
     */
    _handleIntersection(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const element = entry.target;
                const callback = this.loadingCallbacks.get(element);
                
                if (callback) {
                    // Execute callback
                    callback();
                    
                    // Stop observing this element
                    this.unobserve(element);
                }
            }
        });
    }
}

/**
 * Chart lazy loading helper
 */
class ChartLazyLoader {
    /**
     * Initialize chart lazy loader
     * 
     * @param {LazyLoader} lazyLoader - LazyLoader instance (optional, will create if not provided)
     */
    constructor(lazyLoader = null) {
        this.lazyLoader = lazyLoader || new LazyLoader({ rootMargin: '100px' });
        this.loadedCharts = new Set();
    }
    
    /**
     * Register a chart container for lazy loading
     * 
     * @param {string|HTMLElement} selector - CSS selector or element
     * @param {Function} renderFunction - Function to render the chart
     * 
     * @example
     * const chartLoader = new ChartLazyLoader();
     * 
     * chartLoader.registerChart('#signal-strength-chart', (container) => {
     *     const ctx = container.getContext('2d');
     *     new Chart(ctx, {
     *         type: 'line',
     *         data: chartData
     *     });
     * });
     */
    registerChart(selector, renderFunction) {
        const container = typeof selector === 'string' 
            ? document.querySelector(selector)
            : selector;
        
        if (!container) {
            console.warn(`Chart container not found: ${selector}`);
            return;
        }
        
        // Add loading indicator
        container.classList.add('chart-loading');
        
        // Register with lazy loader
        this.lazyLoader.observe(container, () => {
            this._loadChart(container, renderFunction);
        });
    }
    
    /**
     * Load and render a chart
     * @private
     */
    _loadChart(container, renderFunction) {
        if (this.loadedCharts.has(container)) {
            return; // Already loaded
        }
        
        try {
            // Remove loading indicator
            container.classList.remove('chart-loading');
            container.classList.add('chart-loaded');
            
            // Render chart
            renderFunction(container);
            
            // Mark as loaded
            this.loadedCharts.add(container);
            
        } catch (error) {
            console.error('Error loading chart:', error);
            container.classList.add('chart-error');
            container.textContent = 'Error loading chart';
        }
    }
    
    /**
     * Disconnect all observers
     */
    disconnect() {
        this.lazyLoader.disconnect();
        this.loadedCharts.clear();
    }
}

/**
 * Request Animation Frame throttle for smooth animations
 * Better than throttle() for visual updates
 * 
 * @param {Function} func - Function to call on next frame
 * @returns {Function} RAF-throttled function
 * 
 * @example
 * const rafUpdate = rafThrottle(() => {
 *     updateScrollIndicator();
 * });
 * 
 * window.addEventListener('scroll', rafUpdate);
 */
function rafThrottle(func) {
    let rafId = null;
    
    return function rafThrottled(...args) {
        if (rafId === null) {
            rafId = requestAnimationFrame(() => {
                func.apply(this, args);
                rafId = null;
            });
        }
    };
}

/**
 * Idle callback wrapper for low-priority work
 * Falls back to setTimeout if requestIdleCallback not available
 * 
 * @param {Function} func - Function to execute when idle
 * @param {Object} options - Options for requestIdleCallback
 * 
 * @example
 * runWhenIdle(() => {
 *     preloadNextPageData();
 * });
 */
function runWhenIdle(func, options = {}) {
    if ('requestIdleCallback' in window) {
        requestIdleCallback(func, options);
    } else {
        // Fallback to setTimeout
        setTimeout(func, 1);
    }
}

/**
 * Performance monitor for tracking metrics
 */
class PerformanceMonitor {
    constructor() {
        this.marks = new Map();
        this.measures = [];
    }
    
    /**
     * Mark a point in time
     * 
     * @param {string} name - Mark name
     */
    mark(name) {
        if ('performance' in window && performance.mark) {
            performance.mark(name);
            this.marks.set(name, performance.now());
        }
    }
    
    /**
     * Measure time between two marks
     * 
     * @param {string} name - Measure name
     * @param {string} startMark - Start mark name
     * @param {string} endMark - End mark name (optional, defaults to now)
     * @returns {number} Duration in milliseconds
     */
    measure(name, startMark, endMark = null) {
        if (!this.marks.has(startMark)) {
            console.warn(`Start mark not found: ${startMark}`);
            return 0;
        }
        
        const startTime = this.marks.get(startMark);
        const endTime = endMark && this.marks.has(endMark)
            ? this.marks.get(endMark)
            : performance.now();
        
        const duration = endTime - startTime;
        
        this.measures.push({
            name,
            startMark,
            endMark,
            duration,
            timestamp: Date.now()
        });
        
        // Log if slow
        if (duration > 1000) {
            console.warn(`Slow operation: ${name} took ${duration.toFixed(2)}ms`);
        }
        
        return duration;
    }
    
    /**
     * Get all measures
     * 
     * @returns {Array} Array of measure objects
     */
    getMeasures() {
        return [...this.measures];
    }
    
    /**
     * Clear all marks and measures
     */
    clear() {
        this.marks.clear();
        this.measures = [];
        
        if ('performance' in window && performance.clearMarks) {
            performance.clearMarks();
            performance.clearMeasures();
        }
    }
}

// Create global instances
const globalLazyLoader = new LazyLoader();
const globalChartLoader = new ChartLazyLoader(globalLazyLoader);
const globalPerfMonitor = new PerformanceMonitor();

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        debounce,
        throttle,
        rafThrottle,
        runWhenIdle,
        LazyLoader,
        ChartLazyLoader,
        PerformanceMonitor,
        globalLazyLoader,
        globalChartLoader,
        globalPerfMonitor
    };
}
