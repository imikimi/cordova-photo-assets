# SEE README.md for API documentation

module.exports =
  getCollections: (successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getCollections', []

  setOptions: (options, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'setOptionsFromJavascript', [options]

  getOptions: (successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getOptionsForJavascript', []

  # TODO - not yet implemented
  getPhoto:  (options, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getPhoto', [options]

