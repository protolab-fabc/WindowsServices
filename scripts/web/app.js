/* ==========================================================================
   NOZOR AI DASHBOARD - CLIENT APPLICATION
   Real-Time WebSockets, RPG Game Master, Model Auto-Switching, Settings Modal
   ========================================================================== */

class NozorDashboard {
  constructor() {
    this.ws = null;
    this.connected = false;
    this.autoScroll = true;
    this.soundEnabled = true;
    this.currentFilter = 'all';
    this.requestCount = 0;
    this.actionCount = 0;
    this.rpgCount = 0;
    this.audioCtx = null;

    this.initElements();
    this.bindEvents();
    this.loadHistory();
    this.connectWebSocket();
    this.startPollingStatus();
  }

  initElements() {
    this.feedEl = document.getElementById('events-feed');
    this.connIndicator = document.getElementById('connection-indicator');
    this.connStatus = document.getElementById('connection-status');
    this.modelName = document.getElementById('model-name');
    this.statRequests = document.getElementById('stat-requests');
    this.statActions = document.getElementById('stat-actions');
    this.statRpg = document.getElementById('stat-rpg');
    this.queueCount = document.getElementById('queue-count');
    this.lastActivity = document.getElementById('last-activity');
    this.onlinePlayersVal = document.getElementById('online-players-val');
    this.rpgAutoState = document.getElementById('rpg-auto-state');
    this.playerInput = document.getElementById('player-target');
    this.promptInput = document.getElementById('prompt-input');
    this.btnSend = document.getElementById('btn-send-instruction');
    this.btnSound = document.getElementById('btn-sound');
    this.btnAutoScroll = document.getElementById('btn-autoscroll');
    this.btnClear = document.getElementById('btn-clear');
    this.filterBtns = document.querySelectorAll('.filter-btn');
    this.chips = document.querySelectorAll('.chip');

    // RPG Event Buttons
    this.btnRpgActions = document.querySelectorAll('.btn-rpg-action');
    this.btnRpgAiRandom = document.getElementById('btn-rpg-ai-random');

    // Settings Modal Elements
    this.btnSettings = document.getElementById('btn-settings');
    this.modalSettings = document.getElementById('modal-settings');
    this.btnCloseModal = document.getElementById('btn-close-modal');
    this.btnCancelConfig = document.getElementById('btn-cancel-config');
    this.btnSaveConfig = document.getElementById('btn-save-config');
    this.cfgApiKey = document.getElementById('cfg-api-key');
    this.cfgCurrentModel = document.getElementById('cfg-current-model');
    this.cfgModelsList = document.getElementById('cfg-models-list');
    this.cfgAutoSwitch = document.getElementById('cfg-auto-switch');
    this.cfgRpgInterval = document.getElementById('cfg-rpg-interval');
    this.cfgRpgEnabled = document.getElementById('cfg-rpg-enabled');
  }

  bindEvents() {
    // Send instruction button
    this.btnSend.addEventListener('click', () => this.sendInstruction());
    this.promptInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
        this.sendInstruction();
      }
    });

    // Sound toggle
    this.btnSound.addEventListener('click', () => {
      this.soundEnabled = !this.soundEnabled;
      this.btnSound.classList.toggle('active', this.soundEnabled);
      this.btnSound.innerHTML = `<span class="icon">${this.soundEnabled ? '🔔' : '🔕'}</span>`;
      if (this.soundEnabled) this.playChime(600, 0.1);
    });

    // Auto-scroll toggle
    this.btnAutoScroll.addEventListener('click', () => {
      this.autoScroll = !this.autoScroll;
      this.btnAutoScroll.classList.toggle('active', this.autoScroll);
      this.btnAutoScroll.title = this.autoScroll ? 'Défilement automatique (Actif)' : 'Défilement automatique (Désactivé)';
    });

    // Clear feed
    this.btnClear.addEventListener('click', () => {
      if (confirm("Voulez-vous effacer l'affichage en direct ?")) {
        this.feedEl.innerHTML = '';
      }
    });

    // Filters
    this.filterBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        this.filterBtns.forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        this.currentFilter = btn.dataset.filter;
        this.applyFilter();
      });
    });

    // Quick suggestion chips
    this.chips.forEach(chip => {
      chip.addEventListener('click', () => {
        this.promptInput.value = chip.dataset.text;
        this.promptInput.focus();
      });
    });

    // RPG Action Buttons
    this.btnRpgActions.forEach(btn => {
      btn.addEventListener('click', () => {
        const eventType = btn.dataset.rpg;
        this.triggerRpgEvent(eventType);
      });
    });

    if (this.btnRpgAiRandom) {
      this.btnRpgAiRandom.addEventListener('click', () => {
        this.triggerRpgEvent('ai_random');
      });
    }

    // Settings Modal
    if (this.btnSettings) {
      this.btnSettings.addEventListener('click', () => this.openSettings());
    }
    if (this.btnCloseModal) {
      this.btnCloseModal.addEventListener('click', () => this.closeSettings());
    }
    if (this.btnCancelConfig) {
      this.btnCancelConfig.addEventListener('click', () => this.closeSettings());
    }
    if (this.btnSaveConfig) {
      this.btnSaveConfig.addEventListener('click', () => this.saveSettings());
    }

    // Close on click outside modal
    if (this.modalSettings) {
      this.modalSettings.addEventListener('click', (e) => {
        if (e.target === this.modalSettings) this.closeSettings();
      });
    }
  }

  async triggerRpgEvent(eventType) {
    const player = this.playerInput ? this.playerInput.value.trim() : 'Vibrions';
    this.playChime(587.33, 0.1);

    try {
      const res = await fetch('/api/rpg/trigger', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ event_type: eventType, target_player: player })
      });

      if (res.ok) {
        this.playFanfare();
      } else {
        alert("Erreur lors du déclenchement de l'événement RPG.");
      }
    } catch (err) {
      alert("Erreur réseau: " + err.message);
    }
  }

  async openSettings() {
    try {
      const res = await fetch('/api/config');
      if (res.ok) {
        const data = await res.json();
        this.cfgApiKey.value = '';
        this.cfgApiKey.placeholder = data.api_key_masked || 'sk-or-v1-...';
        this.cfgCurrentModel.value = data.current_model || 'openrouter/free';
        this.cfgModelsList.value = (data.models || []).join('\n');
        this.cfgAutoSwitch.checked = data.auto_switch !== false;
        if (this.cfgRpgInterval) this.cfgRpgInterval.value = data.rpg_interval_minutes || 15;
        if (this.cfgRpgEnabled) this.cfgRpgEnabled.checked = data.rpg_enabled !== false;
      }
    } catch (e) {
      console.error("Erreur chargement config:", e);
    }
    this.modalSettings.classList.add('active');
  }

  closeSettings() {
    this.modalSettings.classList.remove('active');
  }

  async saveSettings() {
    const rawModels = this.cfgModelsList.value
      .split('\n')
      .map(m => m.trim())
      .filter(m => m.length > 0);

    const payload = {
      current_model: this.cfgCurrentModel.value.trim(),
      models: rawModels,
      auto_switch: this.cfgAutoSwitch.checked,
      rpg_interval_minutes: parseInt(this.cfgRpgInterval.value, 10) || 15,
      rpg_enabled: this.cfgRpgEnabled.checked
    };

    const newKey = this.cfgApiKey.value.trim();
    if (newKey && !newKey.endsWith('...')) {
      payload.api_key = newKey;
    }

    this.btnSaveConfig.disabled = true;
    this.btnSaveConfig.textContent = "Enregistrement...";

    try {
      const res = await fetch('/api/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (res.ok) {
        this.playChime(880, 0.15);
        this.closeSettings();
        if (payload.current_model) {
          this.modelName.textContent = payload.current_model;
        }
      } else {
        alert("Erreur lors de l'enregistrement de la configuration.");
      }
    } catch (err) {
      alert("Erreur réseau: " + err.message);
    } finally {
      this.btnSaveConfig.disabled = false;
      this.btnSaveConfig.textContent = "Enregistrer les paramètres 💾";
    }
  }

  playChime(freq = 523.25, duration = 0.15) {
    if (!this.soundEnabled) return;
    try {
      if (!this.audioCtx) {
        this.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (this.audioCtx.state === 'suspended') {
        this.audioCtx.resume();
      }
      const osc = this.audioCtx.createOscillator();
      const gain = this.audioCtx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, this.audioCtx.currentTime);
      gain.gain.setValueAtTime(0.08, this.audioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, this.audioCtx.currentTime + duration);
      osc.connect(gain);
      gain.connect(this.audioCtx.destination);
      osc.start();
      osc.stop(this.audioCtx.currentTime + duration);
    } catch (e) {
      // audio suspended until user click
    }
  }

  playFanfare() {
    if (!this.soundEnabled) return;
    // Fanfare RPG: C5 -> E5 -> G5 -> C6
    const notes = [523.25, 659.25, 783.99, 1046.50];
    notes.forEach((note, idx) => {
      setTimeout(() => this.playChime(note, 0.18), idx * 100);
    });
  }

  connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws`;

    this.connIndicator.className = 'stat-indicator busy';
    this.connStatus.textContent = 'Connexion...';

    try {
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        this.connected = true;
        this.connIndicator.className = 'stat-indicator online';
        this.connStatus.textContent = 'En ligne (Live)';
      };

      this.ws.onmessage = (event) => {
        try {
          const payload = JSON.parse(event.data);
          this.handleEvent(payload);
        } catch (err) {
          console.error("Erreur parsing WebSocket message", err);
        }
      };

      this.ws.onclose = () => {
        this.connected = false;
        this.connIndicator.className = 'stat-indicator offline';
        this.connStatus.textContent = 'Déconnecté';
        setTimeout(() => this.connectWebSocket(), 3000);
      };

      this.ws.onerror = (err) => {
        console.warn("WebSocket error:", err);
      };
    } catch (e) {
      this.connIndicator.className = 'stat-indicator offline';
      this.connStatus.textContent = 'Hors ligne';
      setTimeout(() => this.connectWebSocket(), 5000);
    }
  }

  async loadHistory() {
    try {
      const res = await fetch('/api/history');
      if (res.ok) {
        const events = await res.json();
        events.forEach(ev => this.renderEventCard(ev, false));
        if (this.autoScroll) this.scrollToBottom();
      }
    } catch (e) {
      console.log("No previous history available yet.");
    }
  }

  async startPollingStatus() {
    setInterval(async () => {
      try {
        const res = await fetch('/api/status');
        if (res.ok) {
          const data = await res.json();
          if (data.model) this.modelName.textContent = data.model;
          if (data.requests_count !== undefined) this.statRequests.textContent = data.requests_count;
          if (data.actions_count !== undefined) this.statActions.textContent = data.actions_count;
          if (data.rpg_events_count !== undefined && this.statRpg) this.statRpg.textContent = data.rpg_events_count;
          if (data.queue_length !== undefined) this.queueCount.textContent = `${data.queue_length} requêtes`;
          if (data.last_active) this.lastActivity.textContent = data.last_active;

          // Online players
          if (data.online_players && this.onlinePlayersVal) {
            this.onlinePlayersVal.textContent = data.online_players.length > 0
              ? data.online_players.join(', ')
              : 'Aucun joueur';
          }

          // RPG state
          if (this.rpgAutoState) {
            this.rpgAutoState.textContent = data.rpg_enabled
              ? `Toutes les ${data.rpg_interval} min`
              : 'Désactivé';
          }
        }
      } catch (e) {
        // silent fallback
      }
    }, 3000);
  }

  async sendInstruction() {
    const player = this.playerInput.value.trim() || 'Vibrions';
    const instruction = this.promptInput.value.trim();
    if (!instruction) return;

    this.btnSend.disabled = true;
    this.btnSend.innerHTML = `<span class="btn-text">Envoi en cours...</span>`;

    try {
      const res = await fetch('/api/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ player, instruction })
      });

      if (res.ok) {
        this.promptInput.value = '';
        this.playChime(880, 0.1);
      } else {
        alert("Erreur lors de l'envoi de l'instruction.");
      }
    } catch (err) {
      alert("Erreur réseau: " + err.message);
    } finally {
      this.btnSend.disabled = false;
      this.btnSend.innerHTML = `<span class="btn-text">Envoyer l'instruction</span><span class="btn-icon">⚡</span>`;
    }
  }

  handleEvent(event) {
    if (event.type === 'model_update') {
      if (event.model) this.modelName.textContent = event.model;
      return;
    }

    this.renderEventCard(event, true);
    if (this.autoScroll) this.scrollToBottom();

    // Audio alerts
    if (event.type === 'rpg_event') {
      this.playFanfare();
    } else if (event.type === 'speech') {
      this.playChime(659.25, 0.2);
    } else if (event.type === 'request') {
      this.playChime(523.25, 0.15);
    } else if (event.type === 'model_switch') {
      this.playChime(440, 0.3);
    }
  }

  renderEventCard(ev, animate = true) {
    if (ev.type === 'speech' && (!ev.content || !ev.content.trim())) {
      return;
    }

    const card = document.createElement('div');
    card.className = `event-card event-${ev.type || 'system'}`;
    card.dataset.type = ev.type || 'system';

    const timestamp = ev.timestamp ? new Date(ev.timestamp).toLocaleTimeString() : new Date().toLocaleTimeString();

    let contentHtml = '';

    switch (ev.type) {
      case 'rpg_event':
        this.rpgCount++;
        if (this.statRpg) this.statRpg.textContent = this.rpgCount;
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-rpg_event">${this.escapeHtml(ev.icon || '⚔️')} ÉVÉNEMENT RPG</span>
              <span class="event-player-tag">Cible : ${this.escapeHtml(ev.target_player || 'Tous')}</span>
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <div class="rpg-card-title">${this.escapeHtml(ev.name || 'Événement RPG')}</div>
            <div class="rpg-lore-box">"${this.escapeHtml(ev.lore || '')}"</div>
            <div class="rpg-meta-row">
              <span class="rpg-meta-pill">Titre affiché : <strong>${this.escapeHtml(ev.title || '')}</strong></span>
              <span class="rpg-meta-pill">Actions : <strong>${ev.commands_count || 0} commandes exécutées</strong></span>
            </div>
          </div>
        `;
        break;

      case 'speech':
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-speech">🗣️ NOZOR DIT</span>
              ${ev.player ? `<span class="event-player-tag">Pour : ${this.escapeHtml(ev.player)}</span>` : ''}
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <div class="speech-bubble speech-nozor">
              ${this.formatSpeech(ev.content || '')}
            </div>
          </div>
        `;
        break;

      case 'request':
        this.requestCount++;
        this.statRequests.textContent = this.requestCount;
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-request">📥 JOUEUR</span>
              <span class="event-player-tag">${this.escapeHtml(ev.player || 'Inconnu')}</span>
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <div class="request-content">"${this.escapeHtml(ev.instruction || '')}"</div>
            ${ev.position ? `<div class="request-coords">📍 Position : [${ev.position.map(n => typeof n === 'number' ? n.toFixed(1) : n).join(', ')}]</div>` : ''}
          </div>
        `;
        break;

      case 'thought':
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-thought">🧠 RÉFLEXION IA</span>
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <div class="thought-text">${this.escapeHtml(ev.content || '')}</div>
          </div>
        `;
        break;

      case 'action':
        this.actionCount++;
        this.statActions.textContent = this.actionCount;
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-action">⚙️ ACTION / OUTIL</span>
              <span class="event-player-tag">${this.escapeHtml(ev.tool || 'rcon')}</span>
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <div class="command-box">
              <div class="cmd-line">▶ ${this.escapeHtml(ev.command || '')}</div>
              ${ev.output ? `<div class="cmd-output">${this.escapeHtml(ev.output)}</div>` : ''}
            </div>
          </div>
        `;
        break;

      case 'model_switch':
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-model_switch">🔄 BASCULE AUTOMATIQUE</span>
              <span class="event-player-tag">${this.escapeHtml(ev.new_model || '')}</span>
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <div class="switch-alert-box">
              <strong>${this.escapeHtml(ev.reason || 'Bascule de modèle')} :</strong>
              <p>Le modèle précédent (<code>${this.escapeHtml(ev.old_model || '')}</code>) a été remplacé automatiquement par <strong>${this.escapeHtml(ev.new_model || '')}</strong> pour garantir la continuité de service.</p>
            </div>
          </div>
        `;
        break;

      default:
        contentHtml = `
          <div class="event-header">
            <div class="event-meta">
              <span class="event-badge badge-system">SYSTEM</span>
              <span class="event-time">${timestamp}</span>
            </div>
          </div>
          <div class="event-body">
            <p>${this.escapeHtml(ev.content || JSON.stringify(ev))}</p>
          </div>
        `;
    }

    card.innerHTML = contentHtml;

    if (this.currentFilter !== 'all' && this.currentFilter !== ev.type) {
      card.style.display = 'none';
    }

    this.feedEl.appendChild(card);
  }

  applyFilter() {
    const cards = this.feedEl.querySelectorAll('.event-card');
    cards.forEach(card => {
      const type = card.dataset.type;
      if (this.currentFilter === 'all' || this.currentFilter === type) {
        card.style.display = 'block';
      } else {
        card.style.display = 'none';
      }
    });
  }

  scrollToBottom() {
    this.feedEl.scrollTop = this.feedEl.scrollHeight;
  }

  formatSpeech(text) {
    return this.escapeHtml(text)
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/\n/g, '<br>');
  }

  escapeHtml(str) {
    if (typeof str !== 'string') return String(str);
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
}

document.addEventListener('DOMContentLoaded', () => {
  window.dashboard = new NozorDashboard();
});
