# SEE README.md for API documentation

module.exports =
  ###
  on success:
  successCallback [
    # one or more collections with the following format:
    {
      collectionKey:        "all"
      collectionName:       "Camera Roll"
      estimatedAssetCount:  2000
    }
  ]
  ###
  getCollections: (successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getCollections', []

  ###
  options:
    thumbnailSize:        (pixels)
    thumbnailQuality:     (0-100)
    limit:                (int >= 1) number of thumbnails to return starting from the current offset.
    offset:               (int >= 0) current thumbnail offset
    currentCollectionKey: (string) Use "all" for all local images. Otherwise, get collection keys from getCollections
  ###
  setOptions: (options, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'setOptionsFromJavascript', [options]

  getOptions: (successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getOptionsForJavascript', []

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

###
photoAssetsChanged event:

Gets triggered:
  Whenever setOptions is called (and options actually change)
  Whenever iOS notifies us of changes

document.addEventListener 'photoAssetsChanged', ({details})->
  {collection, offset, limit, assets} = details
  {collectionKey, collectionName, estimatedAssetCount} = collection

  console.log "#{collectionName} assets: #{offset} to #{offset + assets.length - 1}:"
  for asset in assets
    {
      pixelWidth, pixelHeight, thumbnailUrl, mediaType, creationDate,
      modificationDate
    } = asset
    console.log "asset #{offset++}", asset

  if assets.length == limit
    PhotoAssets.setAssetWindow offset + limit, limit

###
# helloTest = ->
#   PhotoAssets.echoBackHello 'Cordova World',
#     (message) -> alert message
#   , -> alert 'Error calling Hello Plugin'

# document.addEventListener 'deviceready', helloTest, false
