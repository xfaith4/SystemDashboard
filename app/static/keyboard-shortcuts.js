// Keyboard Shortcuts System

/**
 * KeyboardShortcuts - Global keyboard shortcut handler
 */
const KeyboardShortcuts = {
  shortcuts: new Map(),
  enabled: true,
  helpVisible: false,

  /**
   * Initialize keyboard shortcuts
   */
  init() {
    document.addEventListener('keydown', (e) => this.handleKeyPress(e));
    
    // Register default shortcuts
    this.register({
      key: '?',
      description: 'Show keyboard shortcuts',
      handler: () => this.showHelp()
    });

    this.register({
      key: 'Escape',
      description: 'Close dialogs or cancel',
      handler: () => this.handleEscape()
    });

    this.register({
      key: 'r',
      ctrl: true,
      description: 'Refresh current page',
      handler: (e) => {
        e.preventDefault();
        window.location.reload();
      }
    });

    this.register({
      key: 'h',
      description: 'Go to home/overview',
      handler: () => {
        window.location.href = '/';
      }
    });

    this.register({
      key: 'e',
      description: 'Go to system events',
      handler: () => {
        window.location.href = '/events';
      }
    });

    this.register({
      key: 'l',
      description: 'Go to LAN overview',
      handler: () => {
        window.location.href = '/lan';
      }
    });

    this.register({
      key: 'r',
      description: 'Go to router logs',
      handler: () => {
        window.location.href = '/router';
      }
    });

    this.register({
      key: 'w',
      description: 'Go to Wi-Fi clients',
      handler: () => {
        window.location.href = '/wifi';
      }
    });

    // Search focus
    this.register({
      key: '/',
      description: 'Focus search input',
      handler: (e) => {
        e.preventDefault();
        const searchInput = document.querySelector('input[type="search"], input[type="text"][placeholder*="search" i], #searchInput');
        if (searchInput) {
          searchInput.focus();
          searchInput.select();
        }
      }
    });

    // Page navigation
    this.register({
      key: 'ArrowLeft',
      alt: true,
      description: 'Navigate back',
      handler: (e) => {
        e.preventDefault();
        window.history.back();
      }
    });

    this.register({
      key: 'ArrowRight',
      alt: true,
      description: 'Navigate forward',
      handler: (e) => {
        e.preventDefault();
        window.history.forward();
      }
    });
  },

  /**
   * Register a keyboard shortcut
   */
  register(options) {
    const {
      key,
      ctrl = false,
      alt = false,
      shift = false,
      meta = false,
      description = '',
      handler,
      category = 'General'
    } = options;

    const shortcutKey = this.makeKey(key, ctrl, alt, shift, meta);
    this.shortcuts.set(shortcutKey, {
      key,
      ctrl,
      alt,
      shift,
      meta,
      description,
      handler,
      category
    });
  },

  /**
   * Unregister a keyboard shortcut
   */
  unregister(key, ctrl = false, alt = false, shift = false, meta = false) {
    const shortcutKey = this.makeKey(key, ctrl, alt, shift, meta);
    this.shortcuts.delete(shortcutKey);
  },

  /**
   * Create a unique key for the shortcut
   */
  makeKey(key, ctrl, alt, shift, meta) {
    const parts = [];
    if (ctrl) parts.push('Ctrl');
    if (alt) parts.push('Alt');
    if (shift) parts.push('Shift');
    if (meta) parts.push('Meta');
    parts.push(key.toLowerCase());
    return parts.join('+');
  },

  /**
   * Handle key press
   */
  handleKeyPress(e) {
    if (!this.enabled) return;

    // Don't trigger shortcuts when typing in inputs (except for specific keys)
    if (this.isTyping(e) && !this.isAllowedWhileTyping(e.key)) {
      return;
    }

    const shortcutKey = this.makeKey(
      e.key,
      e.ctrlKey,
      e.altKey,
      e.shiftKey,
      e.metaKey
    );

    const shortcut = this.shortcuts.get(shortcutKey);
    if (shortcut) {
      shortcut.handler(e);
    }
  },

  /**
   * Check if user is typing in an input
   */
  isTyping(e) {
    const target = e.target;
    return (
      target.tagName === 'INPUT' ||
      target.tagName === 'TEXTAREA' ||
      target.tagName === 'SELECT' ||
      target.isContentEditable
    );
  },

  /**
   * Check if key is allowed even while typing
   */
  isAllowedWhileTyping(key) {
    return ['Escape', 'F1', 'F2', 'F3', 'F4', 'F5'].includes(key);
  },

  /**
   * Handle escape key
   */
  handleEscape() {
    // Close help dialog
    if (this.helpVisible) {
      this.hideHelp();
      return;
    }

    // Close confirm dialog
    if (window.ConfirmDialog) {
      ConfirmDialog.hide();
    }

    // Blur active input
    if (document.activeElement.tagName === 'INPUT' || 
        document.activeElement.tagName === 'TEXTAREA') {
      document.activeElement.blur();
    }
  },

  /**
   * Show keyboard shortcuts help
   */
  showHelp() {
    if (this.helpVisible) return;
    this.helpVisible = true;

    // Group shortcuts by category
    const categories = {};
    this.shortcuts.forEach((shortcut) => {
      if (!categories[shortcut.category]) {
        categories[shortcut.category] = [];
      }
      categories[shortcut.category].push(shortcut);
    });

    // Create help dialog
    const overlay = document.createElement('div');
    overlay.className = 'keyboard-shortcuts-overlay';
    overlay.id = 'keyboard-shortcuts-help';

    const dialog = document.createElement('div');
    dialog.className = 'keyboard-shortcuts-dialog';

    let html = `
      <div class="keyboard-shortcuts-header">
        <h2>Keyboard Shortcuts</h2>
        <button class="keyboard-shortcuts-close" aria-label="Close">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="18" y1="6" x2="6" y2="18"/>
            <line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>
      <div class="keyboard-shortcuts-body">
    `;

    for (const [category, shortcuts] of Object.entries(categories)) {
      html += `<div class="keyboard-shortcuts-category">`;
      html += `<h3>${category}</h3>`;
      html += `<div class="keyboard-shortcuts-list">`;
      
      shortcuts.forEach(shortcut => {
        const keys = [];
        if (shortcut.ctrl) keys.push('Ctrl');
        if (shortcut.alt) keys.push('Alt');
        if (shortcut.shift) keys.push('Shift');
        if (shortcut.meta) keys.push('⌘');
        keys.push(this.formatKey(shortcut.key));

        html += `
          <div class="keyboard-shortcut-item">
            <div class="keyboard-shortcut-keys">
              ${keys.map(k => `<kbd>${k}</kbd>`).join(' + ')}
            </div>
            <div class="keyboard-shortcut-description">${shortcut.description}</div>
          </div>
        `;
      });

      html += `</div></div>`;
    }

    html += `</div>`;
    dialog.innerHTML = html;
    overlay.appendChild(dialog);
    document.body.appendChild(overlay);

    // Handle close
    const closeBtn = dialog.querySelector('.keyboard-shortcuts-close');
    const handleClose = () => this.hideHelp();
    closeBtn.onclick = handleClose;
    overlay.onclick = (e) => {
      if (e.target === overlay) handleClose();
    };
  },

  /**
   * Hide keyboard shortcuts help
   */
  hideHelp() {
    const help = document.getElementById('keyboard-shortcuts-help');
    if (help) {
      help.remove();
      this.helpVisible = false;
    }
  },

  /**
   * Format key name for display
   */
  formatKey(key) {
    const keyNames = {
      'ArrowLeft': '←',
      'ArrowRight': '→',
      'ArrowUp': '↑',
      'ArrowDown': '↓',
      'Escape': 'Esc',
      ' ': 'Space'
    };
    return keyNames[key] || key.toUpperCase();
  },

  /**
   * Enable shortcuts
   */
  enable() {
    this.enabled = true;
  },

  /**
   * Disable shortcuts
   */
  disable() {
    this.enabled = false;
  }
};

// Initialize on load
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => KeyboardShortcuts.init());
} else {
  KeyboardShortcuts.init();
}

// Make available globally
window.KeyboardShortcuts = KeyboardShortcuts;
