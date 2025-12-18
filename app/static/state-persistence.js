// State Persistence - Remember search and filter state across navigation

/**
 * StatePersistence - Save and restore page state using localStorage
 */
const StatePersistence = {
  storage: window.localStorage,
  prefix: 'dashboard_',

  /**
   * Save state for a page
   */
  saveState(pageKey, state) {
    try {
      const key = this.prefix + pageKey;
      const data = {
        state,
        timestamp: Date.now()
      };
      this.storage.setItem(key, JSON.stringify(data));
    } catch (error) {
      console.warn('Failed to save state:', error);
    }
  },

  /**
   * Load state for a page
   */
  loadState(pageKey, maxAge = 3600000) { // Default: 1 hour
    try {
      const key = this.prefix + pageKey;
      const item = this.storage.getItem(key);
      
      if (!item) return null;
      
      const data = JSON.parse(item);
      
      // Check if state is expired
      if (maxAge && (Date.now() - data.timestamp) > maxAge) {
        this.clearState(pageKey);
        return null;
      }
      
      return data.state;
    } catch (error) {
      console.warn('Failed to load state:', error);
      return null;
    }
  },

  /**
   * Clear state for a page
   */
  clearState(pageKey) {
    try {
      const key = this.prefix + pageKey;
      this.storage.removeItem(key);
    } catch (error) {
      console.warn('Failed to clear state:', error);
    }
  },

  /**
   * Clear all dashboard states
   */
  clearAll() {
    try {
      const keys = [];
      for (let i = 0; i < this.storage.length; i++) {
        const key = this.storage.key(i);
        if (key && key.startsWith(this.prefix)) {
          keys.push(key);
        }
      }
      keys.forEach(key => this.storage.removeItem(key));
    } catch (error) {
      console.warn('Failed to clear all states:', error);
    }
  },

  /**
   * Auto-save form inputs
   */
  autoSaveForm(formElement, pageKey, options = {}) {
    if (typeof formElement === 'string') {
      formElement = document.querySelector(formElement);
    }
    
    if (!formElement) return;

    const {
      debounce = 500,
      fields = null, // null = all inputs
      onSave = null,
      onLoad = null
    } = options;

    // Get all inputs
    const inputs = fields ? 
      fields.map(f => typeof f === 'string' ? formElement.querySelector(f) : f).filter(Boolean) :
      Array.from(formElement.querySelectorAll('input, select, textarea'));

    // Load saved state
    const savedState = this.loadState(pageKey);
    if (savedState) {
      this.restoreFormState(inputs, savedState);
      if (onLoad) onLoad(savedState);
    }

    // Set up auto-save
    let timeout;
    const handleChange = () => {
      clearTimeout(timeout);
      timeout = setTimeout(() => {
        const state = this.captureFormState(inputs);
        this.saveState(pageKey, state);
        if (onSave) onSave(state);
      }, debounce);
    };

    inputs.forEach(input => {
      input.addEventListener('input', handleChange);
      input.addEventListener('change', handleChange);
    });

    return {
      save: () => {
        const state = this.captureFormState(inputs);
        this.saveState(pageKey, state);
        return state;
      },
      load: () => {
        return this.loadState(pageKey);
      },
      clear: () => {
        this.clearState(pageKey);
      }
    };
  },

  /**
   * Capture current form state
   */
  captureFormState(inputs) {
    const state = {};
    inputs.forEach(input => {
      const name = input.name || input.id;
      if (!name) return;

      if (input.type === 'checkbox') {
        state[name] = input.checked;
      } else if (input.type === 'radio') {
        if (input.checked) {
          state[name] = input.value;
        }
      } else if (input.tagName === 'SELECT' && input.multiple === true) {
        state[name] = Array.from(input.selectedOptions).map(o => o.value);
      } else {
        state[name] = input.value;
      }
    });
    return state;
  },

  /**
   * Restore form state
   */
  restoreFormState(inputs, state) {
    inputs.forEach(input => {
      const name = input.name || input.id;
      if (!name || !(name in state)) return;

      const value = state[name];

      if (input.type === 'checkbox') {
        input.checked = value;
      } else if (input.type === 'radio') {
        input.checked = input.value === value;
      } else if (input.tagName === 'SELECT' && input.multiple === true) {
        const values = Array.isArray(value) ? value : [value];
        Array.from(input.options).forEach(option => {
          option.selected = values.includes(option.value);
        });
      } else {
        input.value = value;
      }

      // Trigger change event to update any dependent UI
      input.dispatchEvent(new Event('change', { bubbles: true }));
    });
  },

  /**
   * Save scroll position
   */
  saveScrollPosition(pageKey) {
    const state = {
      scrollX: window.scrollX,
      scrollY: window.scrollY
    };
    this.saveState(pageKey + '_scroll', state);
  },

  /**
   * Restore scroll position
   */
  restoreScrollPosition(pageKey, delay = 100) {
    const state = this.loadState(pageKey + '_scroll', 60000); // 1 minute max age
    if (state) {
      setTimeout(() => {
        window.scrollTo(state.scrollX, state.scrollY);
      }, delay);
    }
  },

  /**
   * Track navigation history
   */
  trackNavigation(pageKey) {
    // Save scroll position before navigating away
    window.addEventListener('beforeunload', () => {
      this.saveScrollPosition(pageKey);
    });

    // Restore on page load
    if (document.readyState === 'complete') {
      this.restoreScrollPosition(pageKey);
    } else {
      window.addEventListener('load', () => {
        this.restoreScrollPosition(pageKey);
      });
    }
  }
};

/**
 * SearchPersistence - Specific implementation for search/filter forms
 */
const SearchPersistence = {
  /**
   * Set up search persistence for a page
   */
  setup(pageKey, options = {}) {
    const {
      searchInput,      // Search input selector or element
      filterSelects,    // Array of filter select selectors or elements
      onRestore,        // Callback when state is restored
      autoSave = true,  // Auto-save on changes
      maxAge = 3600000  // Max age of saved state (1 hour)
    } = options;

    // Load saved state
    const savedState = StatePersistence.loadState(pageKey, maxAge);
    let stateRestored = false;

    // Restore search input
    if (searchInput && savedState) {
      const input = typeof searchInput === 'string' ? 
        document.querySelector(searchInput) : searchInput;
      
      if (input && savedState.search !== undefined) {
        input.value = savedState.search;
        stateRestored = true;
      }
    }

    // Restore filter selects
    if (filterSelects && savedState) {
      filterSelects.forEach((selector, index) => {
        const select = typeof selector === 'string' ? 
          document.querySelector(selector) : selector;
        
        if (select) {
          const key = select.name || select.id || `filter_${index}`;
          if (savedState[key] !== undefined) {
            select.value = savedState[key];
            stateRestored = true;
          }
        }
      });
    }

    // Call onRestore callback
    if (stateRestored && onRestore) {
      onRestore(savedState);
    }

    // Set up auto-save
    if (autoSave) {
      const save = () => {
        const state = {};
        
        // Save search
        if (searchInput) {
          const input = typeof searchInput === 'string' ? 
            document.querySelector(searchInput) : searchInput;
          if (input) {
            state.search = input.value;
          }
        }
        
        // Save filters
        if (filterSelects) {
          filterSelects.forEach((selector, index) => {
            const select = typeof selector === 'string' ? 
              document.querySelector(selector) : selector;
            if (select) {
              const key = select.name || select.id || `filter_${index}`;
              state[key] = select.value;
            }
          });
        }
        
        StatePersistence.saveState(pageKey, state);
      };

      // Attach listeners
      if (searchInput) {
        const input = typeof searchInput === 'string' ? 
          document.querySelector(searchInput) : searchInput;
        if (input) {
          let timeout;
          input.addEventListener('input', () => {
            clearTimeout(timeout);
            timeout = setTimeout(save, 500);
          });
        }
      }

      if (filterSelects) {
        filterSelects.forEach(selector => {
          const select = typeof selector === 'string' ? 
            document.querySelector(selector) : selector;
          if (select) {
            select.addEventListener('change', save);
          }
        });
      }
    }

    return {
      save: () => {
        const state = {};
        if (searchInput) {
          const input = typeof searchInput === 'string' ? 
            document.querySelector(searchInput) : searchInput;
          if (input) state.search = input.value;
        }
        if (filterSelects) {
          filterSelects.forEach((selector, index) => {
            const select = typeof selector === 'string' ? 
              document.querySelector(selector) : selector;
            if (select) {
              const key = select.name || select.id || `filter_${index}`;
              state[key] = select.value;
            }
          });
        }
        StatePersistence.saveState(pageKey, state);
      },
      clear: () => {
        StatePersistence.clearState(pageKey);
      }
    };
  }
};

// Make utilities available globally
window.StatePersistence = StatePersistence;
window.SearchPersistence = SearchPersistence;
