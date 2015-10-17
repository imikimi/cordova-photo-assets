# SEE README.md for API documentation

module.exports =
  getCollections: (successCallback, errorCallback) -> cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getCollections', []
  getPhoto:                 (options, successCallback, errorCallback) -> cordova.exec successCallback, errorCallback, 'PhotoAssets', 'getPhoto', [options]
  subscribe:                (options, successCallback, errorCallback) -> cordova.exec successCallback, errorCallback, 'PhotoAssets', 'subscribe', [options]
  unsubscribe:              (options, successCallback, errorCallback) -> cordova.exec successCallback, errorCallback, 'PhotoAssets', 'unsubscribe', [options]
  updateSubscriptionWindow: (options, successCallback, errorCallback) -> cordova.exec successCallback, errorCallback, 'PhotoAssets', 'updateSubscriptionWindow', [options]

