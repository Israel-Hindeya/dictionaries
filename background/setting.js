define(["jquery", "utils"], function($, utils) {
  var setting;
  setting = {
    configCache: {
      windowWidth: 630,
      windowHeight: 700,
      enableSelectionOnMouseMove: false,
      enableSelectionSK1: true,
      selectionSK1: 'Meta',
      selectionTimeout: 500,
      enablePlainLookup: true,
      enableAmeAudio: false,
      enableBreAudio: false,
      enablePlainSK1: false,
      plainSK1: 'Meta',
      enableMinidict: false,
      enableMouseSK1: false,
      mouseSK1: 'Ctrl',
      openSK1: 'Ctrl',
      openSK2: 'Shift',
      openKey: 'X',
      browserActionType: 'enableMinidict',
      prevDictSK1: 'Ctrl',
      prevDictKey: 'ArrowLeft',
      nextDictSK1: 'Ctrl',
      nextDictKey: 'ArrowRight',
      prevHistorySK1: 'Alt',
      prevHistoryKey: 'ArrowLeft',
      nextHistorySK1: 'Alt',
      nextHistoryKey: 'ArrowRight',
      dictionary: ''
    },
    init: function() {
      var dfd;
      dfd = $.Deferred();
      chrome.storage.sync.get(this.configCache, (obj) => {
        this.configCache = obj;
        chrome.storage.sync.set(obj);
        return dfd.resolve(obj);
      });
      return dfd;
    },
    setValue: function(key, value) {
      if (this.configCache[key] !== value) {
        this.configCache[key] = value;
        chrome.storage.sync.set(this.configCache);
      }
      return value;
    },
    getValue: function(key, defaultValue) {
      var v;
      v = this.configCache[key];
      if (v == null) {
        v = defaultValue;
      }
      return v;
    }
  };
  return setting;
});
