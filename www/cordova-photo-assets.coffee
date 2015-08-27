module.exports =
  ###
  on success:
  successCallback [
    {id:"all",    name:"Camera Roll",     count: 2000}
    {id:"abc123", name:"My Photo Stream", count: 999}
  ]
  ###
  getAssetCollections: (successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getAssetCollections', []

  ###
  options:
    thumbnailSize:  (pixels)
    limit:          (int >= 1) number of thumbnails to return starting from the current offset.
    offset:         (int >= 0) current thumbnail offset
    collection:     (string) assetCollectionKey. Use "all" for all local images. Otherwise, get collection keys from getAssetCollections
  ###
  set: (options, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'setFromJavascript', [options]

  ###
  options:
    maxSize:            (pixels)
    temporaryFilename:  If the name is the same as a previous call, the previous image is overwritten.
                        This is handy so you don't end up with lots of temporary files wasting the users's storage.
  successCallback:
    ({photoUrl, pixelWidth, pixelHeight, originalPixelWidth, originalPixelHeight}) ->

  TODO:
    add options:
      quality: 0-99

    add callback info:
      fileSize:
      exif:     - as much exif data as we can extract

  ###
  getPhoto:  (options, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getPhoto', [options]

# helloTest = ->
#   PhotoAssets.echoBackHello 'Cordova World',
#     (message) -> alert message
#   , -> alert 'Error calling Hello Plugin'

# document.addEventListener 'deviceready', helloTest, false
