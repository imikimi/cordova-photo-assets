module.exports =
  echoBackHello: (name, successCallback, errorCallback) ->
    cordova.exec successCallback, errorCallback, 'PhotoAssets', 'echoBackHello', [ name ]

helloTest = ->
  PhotoAssets.echoBackHello 'Cordova World',
    (message) -> alert message
  , -> alert 'Error calling Hello Plugin'

document.addEventListener 'deviceready', helloTest, false
