module.exports =
  echoBackHello: (name, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'echoBackHello', [ name ]

  ###
  on success:
  successCallback [
    {collectionKey:"1", name:"Camera Roll"}
    {collectionKey:"2", name:"My Photo Stream"}
  ]
  ###
  getAssetCollections: (successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getAssetCollections', []

  # collectionKey is one of the strings provided in the results from getAssetCollections
  selectAssetCollection: (collectionKey, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'selectAssetCollection', [collectionKey]

  # offset and limit are numbers
  # offset should be >= 0
  # limit should be >= 1
  setAssetWindow: (offset, limit, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'selectAssetCollection', [offset, limit]

helloTest = ->
  PhotoAssets.echoBackHello 'Cordova World',
    (message) -> alert message
  , -> alert 'Error calling Hello Plugin'

document.addEventListener 'deviceready', helloTest, false
