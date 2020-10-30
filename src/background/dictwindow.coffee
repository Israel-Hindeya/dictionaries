import setting from "./setting.coffee"
import storage from  "./storage.coffee"
import dict from "./dict.coffee"
import message from "./message.coffee"
import utils from "utils"
import $ from "jquery"

defaultWindowUrl = chrome.extension.getURL('dict.html')

getInfoOfSelectionCode = '''
var getSentence = function() {
    try {
        var selection = window.getSelection();
        var range = selection.getRangeAt(0);
        if (!selection.toString()) return;

        var range1 = range.cloneRange();
        range1.detach();

        selection.modify('move', 'backward', 'sentence');
        selection.modify('extend', 'forward', 'sentence');

        var text = selection.toString().trim();

        selection.removeAllRanges();
        selection.addRange(range1);

        return text;
    } catch (err) {
        // On firefox, unable to get sentence.
    }
};

[window.getSelection().toString().trim(), getSentence()]
'''

class DictWindow
    w: null
    tid: null
    url: null
    word: null
    dictName: null
    savePosInterval: null
    windex: 0

    constructor: ({ @w, @tid, @url, @word, dictName } = {}) ->
        @dictName = dictName || setting.getValue('dictionary') || dict.allDicts[0].dictName

    reset: ()->
        @w = null
        @tid = null
        @url = null
        @word = null
        window.clearInterval(@savePosInterval) if @savePosInterval
        @savePosInterval = null

    open: (url)->
        # bugfix: dont know how why, windowWidth and windowHeight are saved as number, need integer here.
        width = parseInt(setting.getValue('windowWidth'))
        height = parseInt(setting.getValue('windowHeight'))
        left = setting.getValue('windowLeft', Math.round((screen.width / 2) - (width / 2)))
        top = setting.getValue('windowTop', Math.round((screen.height / 2) - (height / 2)))

        # setup the other cloned window 
        if @windex > 0
            top += 50 * @windex
            left += 50 * @windex 

        return new Promise (resolve) =>
            if !@w
                # console.log "[dictWindow] create window position: top: #{top}, left: #{left}, width: #{width}, height: #{height}"
                chrome.windows.create({
                    url: url or defaultWindowUrl,
                    type: 'popup',
                    width: width,
                    height: height,
                    top: if utils.isLinux() then top - screen.availTop else top, # fix top value on Linux, may be chrome's bug.
                    left: if utils.isLinux() then left - screen.availLeft else left, # fix left value on Linux, may be chrome's bug.
                    state: 'normal',
                }, (win)=>
                    @w = win
                    @tid = @w.tabs[0].id
                    @url = url or defaultWindowUrl
                    resolve()

                    if @windex == 0  # only save the main window position
                        @savePosInterval = window.setInterval @saveWindowPosition.bind(this), 3000
                )
            else
                chrome.tabs.update(@tid, {
                    url: url
                }) if url
               
                resolve()
    focus: () ->
        chrome.windows.update(@w.id, {
            focused: true
        }) if @w

    sendMessage: (msg)->
        chrome.tabs.sendMessage(@tid, msg) if @tid

    lookup: (text)->
        url = ''
        text = @word if not text

        if text
            @sendMessage({type: 'querying', text})
            result = await @queryDict(text)
            url = result?.windowUrl

        @open(url)

    queryDict: (text)->
        return unless text

        @word = text
        console.log "[dictWindow] query #{@word} from #{@dictName}"
        return dict.query(text, @dictName)

    saveWindowPosition: ()->
        # console.log 'saveWindowPosition...'
        if @w
            chrome.windows.get @w.id, null, (w)=>
                if w?.width and w?.height
                    # console.log "[dictWindow] update window position: top: #{w.top}, left: #{w.left}, width: #{w.width}, height: #{w.height}"
                    setting.setValue 'windowWidth', w.width
                    setting.setValue 'windowHeight', w.height
                if w?.top? and w?.left?
                    setting.setValue 'windowLeft', w.left
                    setting.setValue 'windowTop', w.top


    updateDict: (dictName) ->
        if @dictName != dictName
            @dictName = dictName
            setting.setValue 'dictionary', dictName

export default {
    dictWindows: [],

    lookup: ({ w, s, sc, sentence } = {}) ->
        storage.addHistory { w, s, sc, sentence } if w and s  # ignore lookup from options page
        @dictWindows.forEach (win)-> win.lookup(w)
    
    focus: () ->
        i = @dictWindows.length 
        while i  
            i -= 1 
            @dictWindows[i].focus()

    create: () ->
        win = new DictWindow()
        win.windex = @dictWindows.length
        @dictWindows.push win 
        return win 
    
    getByTab: (tid) ->
        for win in @dictWindows 
            if win.tid == tid 
                return win 

    init: () ->
        @create()

        chrome.windows.onRemoved.addListener (wid)=>
            @dictWindows.forEach (win)->
                if win.w?.id == wid
                    win.reset()
            
            # clear closed window
            @dictWindows = @dictWindows.filter (win, i)-> i == 0 or win.w 

        chrome.browserAction.onClicked.addListener (tab) =>
            chrome.tabs.executeScript {
                code: getInfoOfSelectionCode 
            }, (res) =>
                [w, sentence] = res?[0] or []
                @lookup({ w, sentence, s: tab.url, sc: tab.title })
                @focus()

        chrome.contextMenus.create {
            title: "Look up '%s' in dictionaries",
            contexts: ["selection"],
            onclick: (info, tab) =>
                w = info.selectionText?.trim()
                if w 
                    chrome.tabs.executeScript {
                        code: getInfoOfSelectionCode 
                    }, (res) =>
                        [w, sentence] = res?[0] or []
                        @lookup({ w, sentence, s: tab.url, sc: tab.title })
                        @focus()
        }

        message.on 'look up', ({ dictName, w, s, sc, sentence, means, newDictWindow }) =>
            if means == 'mouse'
                if not setting.getValue('enableMinidict')
                    return

            if dictName # only change the main window or in new window.
                if newDictWindow 
                    targetWin = @create()
                    targetWin.updateDict(dictName)
                    targetWin.lookup(@dictWindows[0].word)

                else 
                    @dictWindows[0].updateDict dictName 
                    @dictWindows[0].lookup(w?.trim())
                    @focus()

            else 
                @lookup({ w: w?.trim() })
                @focus()

        message.on 'query', (request, sender) =>
            dictName = request.dictName
            w = request.w
            
            if request.nextDict
                dictName = dict.getNextDict(dictName).dictName
            else if request.previousDict
                dictName = dict.getPreviousDict(dictName).dictName
            
            if request.previousWord
                w = storage.getPrevious(w, true)?.w
            else if request.nextWord
                w = storage.getNext(w, true)?.w
            else if w
                storage.addHistory { w }

            if request.newDictWindow
                targetWin = @create()
                targetWin.updateDict(dictName)
                targetWin.lookup(w)
            else 
                senderWin = @getByTab(sender.tab.id)
                senderWin?.updateDict(dictName)

                @dictWindows.forEach (win)->
                    if win.w and win.w != senderWin.w 
                        win.lookup(w)
                
                return senderWin.queryDict(w)

        message.on 'dictionary', (request, sender) =>
            win = @getByTab(sender.tab.id)

            if win or request.optionsPage
                currentDictName = win?.dictName || setting.getValue('dictionary')

                if win 
                    w = win.word
                    r = storage.getRating(w)
                    previous = storage.getPrevious(w)
                    history = storage.getHistory(w, 8) # at most show 8 words in the history list on dictionary header.

                nextDictName = dict.getNextDict(currentDictName).dictName
                previousDictName = dict.getPreviousDict(currentDictName).dictName
                
                return { allDicts: dict.allDicts, history, currentDictName, nextDictName, previousDictName, previous, w, r }
        
        message.on 'dictionary history', (request, sender) =>
            history = storage.getHistory(request.word, 8) # at most show 8 words in the history list on dictionary header.
            return { history }

        message.on 'injected', (request, sender) =>
            win = @getByTab sender.tab.id 
            if win 
                d = dict.getDict(win.dictName)
                if d.css
                    chrome.tabs.insertCSS win.tid, {
                        runAt: "document_start",
                        code: d.css
                    }

                return {
                    dictUrl: chrome.extension.getURL('dict.html'),
                    cardUrl: chrome.extension.getURL('card.html'),
                    dict: d,
                    word: win.word 
                }
           
        message.on 'window resize', (request, sender) =>
            @getByTab(sender.tab.id)?.saveWindowPosition()

        message.on 'sendToDict', ( request, sender ) =>
            @getByTab(sender.tab.id)?.sendMessage request

        message.on 'get wikipedia', ( request, sender ) =>
            win = @getByTab(sender.tab.id)

            return if not win?.word 
            return if setting.getValue 'disableWikipediaCard'
            if utils.isEnglish win.word 
                return $.get "https://en.m.wikipedia.org/api/rest_v1/page/summary/" + win.word
            else if utils.isChinese(win.word) and setting.getValue "enableLookupChinese"
                return $.get "https://zh.wikipedia.org/api/rest_v1/page/summary/" + win.word
            else if utils.isJapanese win.word
                return $.get "https://ja.wikipedia.org/api/rest_v1/page/summary/" + win.word

}