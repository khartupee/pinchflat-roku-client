sub init()
    print "MainScene: init() started"

    ' Find UI components
    m.videoList = m.top.findNode("videoList")
    m.videoPlayer = m.top.findNode("videoPlayer")
    m.previewPoster = m.top.findNode("previewPoster")
    m.previewTitle = m.top.findNode("previewTitle")
    m.previewDescription = m.top.findNode("previewDescription")
    m.posterDelayTimer = m.top.findNode("posterDelayTimer")
    m.positionSaveTimer = m.top.findNode("positionSaveTimer")
    m.emptyStateLabel = m.top.findNode("emptyStateLabel")

    ' Load settings from registry
    loadSettings()

    ' Thumbnail cache: maps video ID to local file path
    m.thumbnailCache = {}
    m.feedLoaded = false
    m.launchBeaconFired = false
    m.rawVideoData = []
    m.lastFocusedIndex = -1

    if m.videoList <> invalid
        m.videoList.setFocus(true)
        m.videoList.itemComponentName = "CompactRow"
        m.videoList.observeField("itemSelected", "onVideoSelected")
        m.videoList.observeField("itemFocused", "onVideoFocused")
        print "MainScene: 'videoList' node found and focused."
    else
        print "ERROR: Could not find 'videoList' node in MainScene.xml."
    end if

    if m.posterDelayTimer <> invalid
        m.posterDelayTimer.observeField("fire", "onPosterDelayTimerFire")
    end if

    if m.positionSaveTimer <> invalid
        m.positionSaveTimer.observeField("fire", "onPositionSaveTimerFire")
    end if

    ' Deep linking: create InputTask to listen for roInput events
    m.inputTask = CreateObject("roSGNode", "InputTask")
    m.inputTask.observeField("inputData", "onDeepLinkInput")
    m.inputTask.control = "RUN"

    ' If no server URL configured, prompt user to set one
    if m.serverURL = ""
        showServerInputDialog()
    else
        loadFeed()
    end if
end sub

sub loadFeed()
    print "MainScene: Spawning APITask..."
    m.feedLoaded = true
    m.apiTask = CreateObject("roSGNode", "APITask")
    m.apiTask.observeField("content", "onFeedLoaded")
    m.apiTask.observeField("sources", "onSourcesLoaded")
    m.apiTask.observeField("thumbnailResult", "onThumbnailLoaded")
    m.apiTask.observeField("errorMessage", "onAPIError")
    m.apiTask.serverURL = m.serverURL
    m.apiTask.control = "RUN"
end sub

sub onFeedLoaded()
    print "MainScene: onFeedLoaded() triggered!"
    newContent = m.apiTask.content
    if newContent <> invalid and newContent.Count() > 0
        print "MainScene: Received "; newContent.Count(); " items from APITask."

        ' Cache raw data for layout switching
        m.rawVideoData = newContent

        ' Hide empty state if showing
        if m.emptyStateLabel <> invalid then m.emptyStateLabel.visible = false

        buildContentTree()

        ' Fire AppLaunchComplete beacon (only once per launch)
        if not m.launchBeaconFired
            m.top.signalBeacon("AppLaunchComplete")
            m.launchBeaconFired = true
        end if
    else
        print "MainScene WARNING: APITask returned empty or invalid content."
        if m.emptyStateLabel <> invalid
            m.emptyStateLabel.text = "No videos found on server" + Chr(10) + m.serverURL
            m.emptyStateLabel.visible = true
        end if
    end if
end sub

sub onSourcesLoaded()
    sources = m.apiTask.sources
    if sources = invalid then return

    m.sourceLookup = {}
    for each source in sources
        if source.id <> invalid
            m.sourceLookup[source.id.toStr()] = source
        end if
    end for
    print "MainScene: Cached "; m.sourceLookup.Count(); " source descriptions."
end sub

sub buildContentTree()
    if m.rawVideoData.Count() = 0 then return

    rootNode = CreateObject("roSGNode", "ContentNode")

    if m.layoutMode = "standard"
        for each item in m.rawVideoData
            node = createVideoNode(rootNode, item)
        end for
    else if m.layoutMode = "grouped"
        sortedData = sortAndGroupData(m.rawVideoData)
        currentSource = ""
        currentSourceId = 0
        for each item in sortedData
            if item.sourceName <> currentSource and item.sourceName <> ""
                currentSource = item.sourceName
                currentSourceId = item.sourceId
                headerNode = rootNode.CreateChild("VideoItemNode")
                headerNode.title = currentSource
                headerNode.isHeader = true
                headerNode.sourceId = currentSourceId
                headerNode.layoutMode = m.layoutMode
            end if
            createVideoNode(rootNode, item)
        end for
    else if m.layoutMode = "compact"
        sortedData = sortAndGroupData(m.rawVideoData)
        currentSource = ""
        currentSourceId = 0
        for each item in sortedData
            if item.sourceName <> currentSource and item.sourceName <> ""
                currentSource = item.sourceName
                currentSourceId = item.sourceId
                headerNode = rootNode.CreateChild("VideoItemNode")
                headerNode.title = currentSource
                headerNode.isHeader = true
                headerNode.sourceId = currentSourceId
                headerNode.layoutMode = m.layoutMode
            end if
            createVideoNode(rootNode, item)
        end for
    end if

    m.videoContent = rootNode
    if m.videoList <> invalid
        m.videoList.content = m.videoContent
        print "MainScene: Bound content to videoList node successfully."

        ' Set initial preview
        onVideoFocused()
    end if
end sub

function createVideoNode(parent as Object, item as Object) as Object
    node = parent.CreateChild("VideoItemNode")
    node.title = item.title
    node.url = item.url
    node.id = item.id
    node.description = item.description
    node.SDPosterUrl = item.SDPosterUrl
    node.HDPosterUrl = item.HDPosterUrl
    node.playbackPosition = item.playbackPosition
    node.durationSeconds = item.durationSeconds
    node.sourceName = item.sourceName
    node.sourceId = item.sourceId
    node.uploadDate = item.uploadDate
    node.layoutMode = m.layoutMode
    return node
end function

function sortAndGroupData(data as Object) as Object
    if data.Count() = 0 then return data
    ' Copy the array so we don't sort the cached original
    sorted = []
    for each item in data
        sorted.Push(item)
    end for
    sorted.SortBy("sourceName")
    return sorted
end function

sub onVideoSelected()
    if m.videoList = invalid then return
    selectedIndex = m.videoList.itemSelected
    if selectedIndex >= 0
        videoIndex = findVideoIndex(selectedIndex)
        if videoIndex >= 0
            playVideo(videoIndex)
        end if
    end if
end sub

function findVideoIndex(contentIndex as Integer) as Integer
    if m.videoContent = invalid then return -1
    if contentIndex < 0 or contentIndex >= m.videoContent.GetChildCount() then return -1
    node = m.videoContent.GetChild(contentIndex)
    if node <> invalid and node.isHeader <> true
        return contentIndex
    end if
    return -1
end function

function findNextVideoIndex(fromIndex as Integer, direction as Integer) as Integer
    if m.videoContent = invalid then return -1
    count = m.videoContent.GetChildCount()
    i = fromIndex + direction
    while i >= 0 and i < count
        node = m.videoContent.GetChild(i)
        if node <> invalid and node.isHeader <> true
            return i
        end if
        i = i + direction
    end while
    return -1
end function

sub onVideoFocused()
    if m.videoList = invalid or m.videoContent = invalid then return

    ' Postpone image fetching while scrolling.
    ' Reset timer on every navigation event.
    if m.posterDelayTimer <> invalid
        m.posterDelayTimer.control = "STOP"
        m.posterDelayTimer.control = "START"
    end if

    ' Update rowFocused field on content nodes to trigger focus rectangle
    newFocusedIndex = m.videoList.itemFocused
    if m.lastFocusedIndex >= 0 and m.lastFocusedIndex < m.videoContent.GetChildCount() and m.lastFocusedIndex <> newFocusedIndex
        oldNode = m.videoContent.GetChild(m.lastFocusedIndex)
        if oldNode <> invalid then oldNode.rowFocused = false
    end if
    if newFocusedIndex >= 0 and newFocusedIndex < m.videoContent.GetChildCount()
        newNode = m.videoContent.GetChild(newFocusedIndex)
        if newNode <> invalid then newNode.rowFocused = true
    end if
    m.lastFocusedIndex = newFocusedIndex
end sub

sub onPosterDelayTimerFire()
    if m.videoList = invalid or m.videoContent = invalid then return
    focusedIndex = m.videoList.itemFocused
    if focusedIndex >= 0 and focusedIndex < m.videoContent.GetChildCount()
        itemNode = m.videoContent.GetChild(focusedIndex)
        if itemNode <> invalid and itemNode.isHeader <> true
            ' Video item - reset to normal layout
            if m.previewTitle <> invalid
                m.previewTitle.text = itemNode.title
                m.previewTitle.translation = [770, 345]
            end if
            if m.previewDescription <> invalid
                m.previewDescription.numLines = 9
                m.previewDescription.height = "250"
                desc = itemNode.description
                if desc = invalid or desc = "" then desc = "No description available."
                m.previewDescription.text = desc
                m.previewDescription.translation = [770, 420]
            end if

            ' Show poster
            if m.previewPoster <> invalid
                m.previewPoster.uri = ""
            end if

            ' Lazy-load thumbnail
            videoId = itemNode.id.toStr()
            if videoId <> "" and videoId <> "invalid"
                if m.thumbnailCache.DoesExist(videoId)
                    ' Already cached, use local path
                    if m.previewPoster <> invalid
                        m.previewPoster.uri = m.thumbnailCache[videoId]
                    end if
                else if itemNode.SDPosterUrl <> "" and itemNode.SDPosterUrl <> invalid
                    ' Request download from APITask
                    m.pendingThumbnailId = videoId
                    m.apiTask.thumbnailRequest = { url: itemNode.SDPosterUrl, id: videoId }
                end if
            end if
        else if itemNode <> invalid and itemNode.isHeader = true
            ' Header item - move labels up into poster area
            if m.previewTitle <> invalid
                m.previewTitle.text = itemNode.title
                m.previewTitle.translation = [770, 85]
            end if
            desc = ""
            if m.sourceLookup <> invalid
                sourceData = m.sourceLookup[itemNode.sourceId.toStr()]
                if sourceData <> invalid and sourceData.description <> invalid
                    desc = sourceData.description
                end if
            end if
            if desc = "" then desc = "No description available."
            if m.previewDescription <> invalid
                m.previewDescription.numLines = 20
                m.previewDescription.height = "520"
                m.previewDescription.text = desc
                m.previewDescription.translation = [770, 120]
            end if
            if m.previewPoster <> invalid then m.previewPoster.uri = ""
        else
            ' Invalid - clear preview
            if m.previewTitle <> invalid then m.previewTitle.text = ""
            if m.previewDescription <> invalid then m.previewDescription.text = ""
            if m.previewPoster <> invalid then m.previewPoster.uri = ""
        end if
    else
        ' No items - clear the preview panel
        if m.previewTitle <> invalid then m.previewTitle.text = ""
        if m.previewDescription <> invalid then m.previewDescription.text = ""
        if m.previewPoster <> invalid then m.previewPoster.uri = ""
    end if
end sub

sub onThumbnailLoaded(event as Object)
    result = event.GetData()
    if result = invalid or result.id = invalid then return

    videoId = result.id
    localPath = result.localPath

    ' Cache the local path
    m.thumbnailCache[videoId] = localPath

    ' Update poster if this is still the focused item
    if m.videoList <> invalid and m.videoContent <> invalid
        focusedIndex = m.videoList.itemFocused
        if focusedIndex >= 0 and focusedIndex < m.videoContent.GetChildCount()
            itemNode = m.videoContent.GetChild(focusedIndex)
            if itemNode <> invalid and itemNode.id.toStr() = videoId
                if m.previewPoster <> invalid
                    m.previewPoster.uri = localPath
                end if
            end if
        end if
    end if
end sub

sub onDeepLinkInput()
    deeplink = m.inputTask.inputData
    if deeplink = invalid then return
    if deeplink.id = "" or deeplink.id = invalid then return

    print "MainScene: Deep link received for contentID="; deeplink.id

    if m.videoContent <> invalid
        for i = 0 to m.videoContent.GetChildCount() - 1
            childNode = m.videoContent.GetChild(i)
            if childNode <> invalid and childNode.id.toStr() = deeplink.id.toStr()
                print "MainScene: Deep link match found, playing video at index "; i
                playVideo(i)
                return
            end if
        end for
    end if

    print "MainScene: Deep link contentID not found: "; deeplink.id
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    handled = false
    if press then
        if m.videoPlayer <> invalid and m.videoPlayer.visible = true
            if key = "back"
                print "Closing video player..."
                if m.positionSaveTimer <> invalid then m.positionSaveTimer.control = "stop"
                saveCurrentPosition()
                m.videoPlayer.control = "stop"
                m.videoPlayer.visible = false
                m.videoList.setFocus(true)
                handled = true
            end if
        else if key = "options"
            showOptionsMenu()
            handled = true
        end if
    end if
    return handled
end function

sub saveCurrentPosition()
    if m.videoPlayer = invalid or m.currentPlayId = invalid then return

    position = m.videoPlayer.position
    if position = invalid then position = 0
    duration = 0
    if m.videoContent <> invalid and m.currentPlayIndex <> invalid
        itemNode = m.videoContent.GetChild(m.currentPlayIndex)
        if itemNode <> invalid
            duration = itemNode.durationSeconds
            if duration = invalid then duration = 0
        end if
    end if

    ' Only save if position is meaningful (> 10s) and not near the end (< 95%)
    if position > 10 and (duration = 0 or position < duration * 0.95)
        print "Saving playback position: "; position; "s for video "; m.currentPlayId
        m.apiTask.actionRequest = { type: "save_progress", videoId: m.currentPlayId, position: Int(position) }

        ' Update local node so UI reflects new position
        if m.videoContent <> invalid and m.currentPlayIndex <> invalid
            itemNode = m.videoContent.GetChild(m.currentPlayIndex)
            if itemNode <> invalid
                itemNode.playbackPosition = Int(position)
            end if
        end if
    end if
end sub

sub onPositionSaveTimerFire()
    saveCurrentPosition()
end sub

sub deleteVideoFromServer(itemIndex as Integer, videoId as String)
    m.apiTask.actionRequest = { type: "delete", videoId: videoId }
    removeVideoFromList(itemIndex)
end sub

sub deleteAndIgnoreVideoFromServer(itemIndex as Integer, videoId as String)
    m.apiTask.actionRequest = { type: "ignore", videoId: videoId }
    removeVideoFromList(itemIndex)
end sub

sub removeVideoFromList(itemIndex as Integer)
    if m.videoContent <> invalid
        childNode = m.videoContent.GetChild(itemIndex)
        if childNode <> invalid
            m.videoContent.removeChild(childNode)
        end if
    end if

    ' Select next or previous item if available
    if m.videoList <> invalid and m.videoContent <> invalid
        count = m.videoContent.GetChildCount()
        if count > 0
            if itemIndex >= count then itemIndex = count - 1
            m.videoList.jumpToItem = itemIndex
        end if
    end if

    onVideoFocused()
end sub

sub playVideo(itemIndex as Integer)
    if m.videoContent <> invalid and m.videoPlayer <> invalid
        itemNode = m.videoContent.GetChild(itemIndex)
        if itemNode <> invalid and itemNode.url <> "" and itemNode.url <> invalid
            print "Launching player for URL: "; itemNode.url

            ' Store current video info for post-play dialog
            m.currentPlayIndex = itemIndex
            m.currentPlayId = itemNode.id.toStr()

            ' Check if we should offer resume
            savedPos = itemNode.playbackPosition
            duration = itemNode.durationSeconds
            if savedPos = invalid then savedPos = 0
            if duration = invalid then duration = 0

            ' Only offer resume if position is > 10s and < 95% of duration
            if savedPos > 10 and (duration = 0 or savedPos < duration * 0.95)
                showResumeDialog(itemIndex, savedPos, duration)
            else
                startPlayback(itemIndex, 0)
            end if
        end if
    end if
end sub

sub showResumeDialog(itemIndex as Integer, savedPos as Integer, duration as Integer)
    scene = m.top.getScene()
    scene.dialog = invalid

    posMinutes = Int(savedPos / 60)
    posSeconds = savedPos mod 60
    posStr = posMinutes.toStr() + ":" + Right("0" + posSeconds.toStr(), 2)

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Resume Playback"
    dialog.message = ["Resume from " + posStr + "?"]
    dialog.buttons = ["Resume", "Start from Beginning", "Cancel"]

    dialog.addFields({
        itemIndex: itemIndex
        savedPos: savedPos
    })

    dialog.observeField("buttonSelected", "onResumeDialogSelected")
    scene.dialog = dialog
end sub

sub onResumeDialogSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    itemIndex = dialog.itemIndex
    savedPos = dialog.savedPos

    scene.dialog = invalid

    if buttonIndex = 0
        startPlayback(itemIndex, savedPos)
    else if buttonIndex = 1
        startPlayback(itemIndex, 0)
    else
        m.videoList.setFocus(true)
    end if
end sub

sub startPlayback(itemIndex as Integer, startPosition as Integer)
    if m.videoContent <> invalid and m.videoPlayer <> invalid
        itemNode = m.videoContent.GetChild(itemIndex)
        if itemNode <> invalid and itemNode.url <> "" and itemNode.url <> invalid
            print "Starting playback at position: "; startPosition

            ' Store current video info for post-play dialog
            m.currentPlayIndex = itemIndex
            m.currentPlayId = itemNode.id.toStr()

            videoContent = CreateObject("roSGNode", "ContentNode")
            videoContent.url = itemNode.url
            videoContent.title = itemNode.title
            videoContent.streamFormat = "mp4"
            if startPosition > 0
                videoContent.playStart = startPosition
            end if

            m.videoPlayer.content = videoContent
            m.videoPlayer.visible = true
            m.videoPlayer.setFocus(true)
            m.videoPlayer.control = "play"

            m.videoPlayer.observeField("state", "onVideoPlayerStateChange")

            if m.positionSaveTimer <> invalid
                m.positionSaveTimer.control = "start"
            end if
        end if
    end if
end sub

sub onVideoPlayerStateChange()
    if m.videoPlayer <> invalid
        state = m.videoPlayer.state
        print "Video player state changed to: "; state
        if state = "finished"
            if m.positionSaveTimer <> invalid then m.positionSaveTimer.control = "stop"
            ' Video completed - clear playback position
            if m.currentPlayId <> invalid
                m.apiTask.actionRequest = { type: "save_progress", videoId: m.currentPlayId, position: 0 }
                if m.videoContent <> invalid and m.currentPlayIndex <> invalid
                    itemNode = m.videoContent.GetChild(m.currentPlayIndex)
                    if itemNode <> invalid
                        itemNode.playbackPosition = 0
                    end if
                end if
            end if
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            showPostPlayDialog()
        else if state = "error"
            if m.positionSaveTimer <> invalid then m.positionSaveTimer.control = "stop"
            m.videoPlayer.control = "stop"
            m.videoPlayer.visible = false
            m.videoList.setFocus(true)
        end if
    end if
end sub

sub showPostPlayDialog()
    if not m.showPostPlayDialogSetting then
        m.videoList.setFocus(true)
        return
    end if

    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Video Finished"
    dialog.message = ["Delete and Ignore this video?"]
    dialog.buttons = ["Delete & Ignore", "Keep Video"]

    dialog.addFields({
        itemIndex: m.currentPlayIndex
        videoId: m.currentPlayId
    })

    dialog.observeField("buttonSelected", "onPostPlayActionSelected")
    scene.dialog = dialog
end sub

sub onPostPlayActionSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    itemIndex = dialog.itemIndex
    videoId = dialog.videoId

    scene.dialog = invalid

    if buttonIndex = 0
        deleteAndIgnoreVideoFromServer(itemIndex, videoId)
    end if

    m.videoList.setFocus(true)
end sub

' ==================== Settings ====================

sub loadSettings()
    sec = CreateObject("roRegistrySection", "AppSettings")

    if sec.Exists("serverURL")
        m.serverURL = sec.Read("serverURL")
    else
        m.serverURL = ""
    end if

    ' Ensure URL uses HTTPS (NGINX proxies redirect HTTP to HTTPS, which breaks PATCH)
    if m.serverURL <> ""
        if Left(m.serverURL, 8) = "https://"
            ' Already HTTPS, good
        else if Left(m.serverURL, 7) = "http://"
            m.serverURL = "https://" + Right(m.serverURL, Len(m.serverURL) - 7)
        else
            m.serverURL = "https://" + m.serverURL
        end if
    end if

    if sec.Exists("showPostPlayDialog")
        m.showPostPlayDialogSetting = sec.Read("showPostPlayDialog") = "true"
    else
        m.showPostPlayDialogSetting = false
        sec.Write("showPostPlayDialog", "true")
        sec.Flush()
    end if

    if sec.Exists("layoutMode")
        m.layoutMode = sec.Read("layoutMode")
    else
        m.layoutMode = "standard"
        sec.Write("layoutMode", "standard")
        sec.Flush()
    end if

    print "MainScene: Loaded settings - serverURL='"; m.serverURL; "' showPostPlayDialog="; m.showPostPlayDialogSetting; " layoutMode="; m.layoutMode
end sub

sub saveSettings()
    sec = CreateObject("roRegistrySection", "AppSettings")
    sec.Write("serverURL", m.serverURL)
    sec.Write("showPostPlayDialog", m.showPostPlayDialogSetting.toStr())
    sec.Write("layoutMode", m.layoutMode)
    sec.Flush()
    print "MainScene: Saved settings - serverURL="; m.serverURL; " showPostPlayDialog="; m.showPostPlayDialogSetting; " layoutMode="; m.layoutMode
end sub

sub showOptionsMenu()
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Pinchflat"
    dialog.message = [m.serverURL]
    dialog.buttons = ["Play", "Delete File", "Delete & Ignore", "Settings", "Cancel"]

    if m.videoList <> invalid and m.videoContent <> invalid
        focusedIndex = m.videoList.itemFocused
        if focusedIndex >= 0
            itemNode = m.videoContent.GetChild(focusedIndex)
            if itemNode <> invalid
                dialog.addFields({
                    itemIndex: focusedIndex
                    videoId: itemNode.id.toStr()
                    videoTitle: itemNode.title
                })
            end if
        end if
    end if

    dialog.observeField("buttonSelected", "onMenuSelected")
    scene.dialog = dialog
end sub

sub onMenuSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    itemIndex = dialog.itemIndex
    videoId = dialog.videoId

    scene.dialog = invalid

    if buttonIndex = 0
        if itemIndex <> invalid then playVideo(itemIndex)
    else if buttonIndex = 1
        if itemIndex <> invalid and videoId <> invalid then deleteVideoFromServer(itemIndex, videoId)
    else if buttonIndex = 2
        if itemIndex <> invalid and videoId <> invalid then deleteAndIgnoreVideoFromServer(itemIndex, videoId)
    else if buttonIndex = 3
        showSettingsDialog()
    end if
end sub

sub showSettingsDialog()
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Settings"

    postPlayStatus = "ON"
    if not m.showPostPlayDialogSetting then postPlayStatus = "OFF"

    layoutNames = { standard: "Standard", grouped: "Grouped", compact: "Compact" }
    layoutLabel = layoutNames[m.layoutMode]
    if layoutLabel = invalid then layoutLabel = "Standard"

    dialog.message = ["Server: " + m.serverURL, "Video Finished Dialog: " + postPlayStatus, "Layout: " + layoutLabel]
    dialog.buttons = ["Change Server Address", "Toggle Video Finished Dialog", "Change Layout", "Close"]

    dialog.observeField("buttonSelected", "onSettingsSelected")
    scene.dialog = dialog
end sub

sub onSettingsSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    if buttonIndex = 0
        showServerInputDialog()
    else if buttonIndex = 1
        togglePostPlayDialog()
    else if buttonIndex = 2
        showLayoutPickerDialog()
    end if
end sub

sub showLayoutPickerDialog()
    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Select Layout Mode"
    dialog.message = ["Choose how videos are displayed in the list:"]
    dialog.buttons = ["Standard", "Grouped", "Compact", "Cancel"]

    dialog.observeField("buttonSelected", "onLayoutPickerSelected")
    scene.dialog = dialog
end sub

sub onLayoutPickerSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    layoutModes = ["standard", "grouped", "compact"]
    if buttonIndex >= 0 and buttonIndex < layoutModes.Count()
        m.layoutMode = layoutModes[buttonIndex]
        saveSettings()

        if m.rawVideoData.Count() > 0
            buildContentTree()
        end if
    end if

    showSettingsDialog()
end sub

sub showServerInputDialog()
    scene = m.top.getScene()
    scene.dialog = invalid

    m.top.signalBeacon("AppDialogInitiate")

    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = "Server Address (IP:port or hostname.example.com)"
    dialog.text = m.serverURL
    dialog.keyboardDomain = "alphanumeric"
    dialog.buttons = ["Save", "Cancel"]

    dialog.observeField("buttonSelected", "onServerInputSelected")
    scene.dialog = dialog
end sub

sub onServerInputSelected()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    m.top.signalBeacon("AppDialogComplete")

    if buttonIndex = 0
        newURL = dialog.text
        newURL = newURL.Trim()

        ' Strip trailing slash
        if Right(newURL, 1) = "/"
            newURL = Left(newURL, Len(newURL) - 1)
        end if

        if newURL <> ""
            ' Ensure HTTPS
            if Left(newURL, 8) = "https://"
                ' Already HTTPS
            else if Left(newURL, 7) = "http://"
                newURL = "https://" + Right(newURL, Len(newURL) - 7)
            else
                newURL = "https://" + newURL
            end if
            m.serverURL = newURL
            saveSettings()

            if m.feedLoaded
                restartFeed()
            else
                loadFeed()
            end if
        end if

        showSettingsDialog()
    else
        ' Cancel pressed - if no URL set yet, prompt again
        if m.serverURL = ""
            showServerInputDialog()
        else
            showSettingsDialog()
        end if
    end if
end sub

sub togglePostPlayDialog()
    m.showPostPlayDialogSetting = not m.showPostPlayDialogSetting
    saveSettings()
    showSettingsDialog()
end sub

sub restartFeed()
    print "MainScene: Restarting feed with serverURL="; m.serverURL
    m.thumbnailCache = {}
    m.apiTask = CreateObject("roSGNode", "APITask")
    m.apiTask.observeField("content", "onFeedLoaded")
    m.apiTask.observeField("sources", "onSourcesLoaded")
    m.apiTask.observeField("thumbnailResult", "onThumbnailLoaded")
    m.apiTask.observeField("errorMessage", "onAPIError")
    m.apiTask.serverURL = m.serverURL
    m.apiTask.control = "RUN"
end sub

sub onAPIError()
    errorMsg = m.apiTask.errorMessage
    if errorMsg = "" or errorMsg = invalid then return

    scene = m.top.getScene()
    scene.dialog = invalid

    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = "Connection Error"
    dialog.message = [errorMsg]
    dialog.buttons = ["Retry", "Change URL"]

    dialog.observeField("buttonSelected", "onAPIErrorAction")
    scene.dialog = dialog
end sub

sub onAPIErrorAction()
    scene = m.top.getScene()
    dialog = scene.dialog
    if dialog = invalid then return

    buttonIndex = dialog.buttonSelected
    scene.dialog = invalid

    if buttonIndex = 0
        loadFeed()
    else if buttonIndex = 1
        showServerInputDialog()
    end if
end sub

