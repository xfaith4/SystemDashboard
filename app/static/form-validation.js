// Form Validation and Autosave System

/**
 * FormValidator - Real-time form validation with visual feedback
 */
const FormValidator = {
  validators: {
    // MAC address validation (AA:BB:CC:DD:EE:FF or AA-BB-CC-DD-EE-FF)
    macAddress(value) {
      if (!value) return { valid: true };
      const pattern = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/;
      return {
        valid: pattern.test(value),
        message: 'Invalid MAC address format. Use AA:BB:CC:DD:EE:FF'
      };
    },

    // IPv4 address validation
    ipAddress(value) {
      if (!value) return { valid: true };
      const parts = value.split('.');
      if (parts.length !== 4) {
        return { valid: false, message: 'IP address must have 4 octets' };
      }
      const valid = parts.every(part => {
        const num = parseInt(part, 10);
        return num >= 0 && num <= 255 && part === num.toString();
      });
      return {
        valid,
        message: valid ? '' : 'Invalid IP address. Each octet must be 0-255'
      };
    },

    // Required field validation
    required(value) {
      const valid = value && value.trim().length > 0;
      return {
        valid,
        message: valid ? '' : 'This field is required'
      };
    },

    // Min length validation
    minLength(value, min) {
      if (!value) return { valid: true };
      const valid = value.length >= min;
      return {
        valid,
        message: valid ? '' : `Must be at least ${min} characters`
      };
    },

    // Max length validation
    maxLength(value, max) {
      if (!value) return { valid: true };
      const valid = value.length <= max;
      return {
        valid,
        message: valid ? '' : `Must be no more than ${max} characters`
      };
    },

    // Alphanumeric with spaces and common punctuation
    alphanumeric(value) {
      if (!value) return { valid: true };
      const pattern = /^[a-zA-Z0-9\s\-_.(),]+$/;
      return {
        valid: pattern.test(value),
        message: 'Only letters, numbers, spaces, and common punctuation allowed'
      };
    },

    // Hostname validation
    hostname(value) {
      if (!value) return { valid: true };
      const pattern = /^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$/;
      return {
        valid: pattern.test(value) && value.length <= 253,
        message: 'Invalid hostname format'
      };
    }
  },

  /**
   * Validate a single field
   */
  validateField(input, rules) {
    const value = input.value;
    const results = [];

    for (const rule of rules) {
      let result;
      if (typeof rule === 'string') {
        // Simple validator name
        result = this.validators[rule](value);
      } else if (typeof rule === 'object') {
        // Validator with parameters
        const { name, ...params } = rule;
        result = this.validators[name](value, ...Object.values(params));
      } else if (typeof rule === 'function') {
        // Custom validator function
        result = rule(value);
      }

      if (!result.valid) {
        results.push(result);
        break; // Stop at first validation error
      }
    }

    return results.length > 0 ? results[0] : { valid: true };
  },

  /**
   * Show validation feedback on input
   */
  showFeedback(input, result) {
    const parent = input.closest('.form-group');
    if (!parent) return;

    // Remove existing feedback
    const existingFeedback = parent.querySelector('.validation-feedback');
    if (existingFeedback) {
      existingFeedback.remove();
    }

    // Update input styling
    input.classList.remove('input-valid', 'input-invalid');
    if (input.value) {
      input.classList.add(result.valid ? 'input-valid' : 'input-invalid');
    }

    // Add feedback message if invalid
    if (!result.valid && result.message) {
      const feedback = document.createElement('div');
      feedback.className = 'validation-feedback validation-error';
      feedback.textContent = result.message;
      parent.appendChild(feedback);
    }
  },

  /**
   * Set up validation for an input field
   */
  setupInput(input, rules, options = {}) {
    const validateAndShow = () => {
      const result = this.validateField(input, rules);
      this.showFeedback(input, result);
      if (options.onChange) {
        options.onChange(result);
      }
      return result;
    };

    // Validate on blur
    input.addEventListener('blur', validateAndShow);

    // Optional: validate on input (with debounce)
    if (options.validateOnInput) {
      let timeout;
      input.addEventListener('input', () => {
        clearTimeout(timeout);
        timeout = setTimeout(validateAndShow, options.debounce || 300);
      });
    }

    return validateAndShow;
  }
};

/**
 * AutoSave - Automatic saving of form data with visual feedback
 */
const AutoSave = {
  instances: new Map(),

  /**
   * Create an autosave instance for a form or field group
   */
  create(options) {
    const {
      fields,           // Array of input elements or selectors
      saveFunction,     // async function(data) that saves the data
      delay = 1000,     // Delay in ms after user stops typing
      statusElement,    // Element to show save status
      onSaveSuccess,    // Callback after successful save
      onSaveError       // Callback after save error
    } = options;

    const instance = {
      fields: [],
      timeout: null,
      saving: false,
      lastSavedData: null,
      options
    };

    // Resolve field selectors to elements
    instance.fields = fields.map(f => 
      typeof f === 'string' ? document.querySelector(f) : f
    ).filter(Boolean);

    // Set up change listeners
    instance.fields.forEach(field => {
      const handleChange = () => {
        if (instance.saving) return;
        
        clearTimeout(instance.timeout);
        this.showStatus(statusElement, 'pending');
        
        instance.timeout = setTimeout(() => {
          this.save(instance);
        }, delay);
      };

      field.addEventListener('input', handleChange);
      field.addEventListener('change', handleChange);
    });

    const id = `autosave-${Date.now()}`;
    this.instances.set(id, instance);
    
    return {
      id,
      save: () => this.save(instance),
      destroy: () => this.instances.delete(id)
    };
  },

  /**
   * Collect data from fields
   */
  collectData(fields) {
    const data = {};
    fields.forEach(field => {
      const name = field.name || field.id;
      if (!name) return;

      if (field.type === 'checkbox') {
        data[name] = field.checked;
      } else if (field.tagName === 'SELECT' && field.multiple) {
        data[name] = Array.from(field.selectedOptions).map(o => o.value);
      } else {
        data[name] = field.value;
      }
    });
    return data;
  },

  /**
   * Check if data has changed
   */
  hasChanged(instance) {
    const currentData = JSON.stringify(this.collectData(instance.fields));
    const lastData = instance.lastSavedData;
    return lastData === null || currentData !== lastData;
  },

  /**
   * Save the data
   */
  async save(instance) {
    if (instance.saving || !this.hasChanged(instance)) {
      return;
    }

    const { saveFunction, statusElement, onSaveSuccess, onSaveError } = instance.options;
    instance.saving = true;
    this.showStatus(statusElement, 'saving');

    try {
      const data = this.collectData(instance.fields);
      await saveFunction(data);
      
      instance.lastSavedData = JSON.stringify(data);
      this.showStatus(statusElement, 'success');
      
      if (onSaveSuccess) {
        onSaveSuccess(data);
      }

      // Clear success message after 2 seconds
      setTimeout(() => {
        this.showStatus(statusElement, 'idle');
      }, 2000);
    } catch (error) {
      console.error('AutoSave error:', error);
      this.showStatus(statusElement, 'error');
      
      if (onSaveError) {
        onSaveError(error);
      }

      // Clear error message after 5 seconds
      setTimeout(() => {
        this.showStatus(statusElement, 'idle');
      }, 5000);
    } finally {
      instance.saving = false;
    }
  },

  /**
   * Show save status
   */
  showStatus(element, status) {
    if (!element) return;

    const messages = {
      idle: '',
      pending: '⋯ Editing',
      saving: '↻ Saving...',
      success: '✓ Saved',
      error: '✕ Failed to save'
    };

    const classes = {
      idle: '',
      pending: 'status-pending',
      saving: 'status-saving',
      success: 'status-success',
      error: 'status-error'
    };

    element.textContent = messages[status] || '';
    element.className = `autosave-status ${classes[status] || ''}`;
  }
};

/**
 * ConfirmDialog - Modal confirmation dialogs
 */
const ConfirmDialog = {
  /**
   * Show a confirmation dialog
   */
  show(options) {
    const {
      title = 'Confirm Action',
      message = 'Are you sure?',
      confirmText = 'Confirm',
      cancelText = 'Cancel',
      type = 'warning', // 'warning', 'danger', 'info'
      onConfirm,
      onCancel
    } = options;

    return new Promise((resolve) => {
      // Remove any existing dialog
      this.hide();

      // Create overlay
      const overlay = document.createElement('div');
      overlay.className = 'confirm-dialog-overlay';
      overlay.id = 'confirm-dialog';

      // Create dialog
      const dialog = document.createElement('div');
      dialog.className = `confirm-dialog confirm-dialog-${type}`;
      
      const icons = {
        warning: '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>',
        danger: '<circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>',
        info: '<circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>'
      };

      dialog.innerHTML = `
        <div class="confirm-dialog-header">
          <svg class="confirm-dialog-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            ${icons[type] || icons.warning}
          </svg>
          <h3 class="confirm-dialog-title">${title}</h3>
        </div>
        <div class="confirm-dialog-body">
          <p class="confirm-dialog-message">${message}</p>
        </div>
        <div class="confirm-dialog-actions">
          <button class="btn-secondary confirm-dialog-cancel">${cancelText}</button>
          <button class="btn-primary confirm-dialog-confirm">${confirmText}</button>
        </div>
      `;

      overlay.appendChild(dialog);
      document.body.appendChild(overlay);

      // Handle confirm
      const confirmBtn = dialog.querySelector('.confirm-dialog-confirm');
      confirmBtn.onclick = () => {
        this.hide();
        if (onConfirm) onConfirm();
        resolve(true);
      };

      // Handle cancel
      const cancelBtn = dialog.querySelector('.confirm-dialog-cancel');
      const handleCancel = () => {
        this.hide();
        if (onCancel) onCancel();
        resolve(false);
      };
      cancelBtn.onclick = handleCancel;
      overlay.onclick = (e) => {
        if (e.target === overlay) handleCancel();
      };

      // Handle escape key
      const handleEscape = (e) => {
        if (e.key === 'Escape') {
          handleCancel();
          document.removeEventListener('keydown', handleEscape);
        }
      };
      document.addEventListener('keydown', handleEscape);

      // Focus confirm button
      confirmBtn.focus();
    });
  },

  /**
   * Hide the dialog
   */
  hide() {
    const dialog = document.getElementById('confirm-dialog');
    if (dialog) {
      dialog.remove();
    }
  }
};

// Make utilities available globally
window.FormValidator = FormValidator;
window.AutoSave = AutoSave;
window.ConfirmDialog = ConfirmDialog;
