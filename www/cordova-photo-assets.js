/*global cordova, module*/

(function(){

  module.exports = {
    echoBackHello: function (name, successCallback, errorCallback) {
        cordova.exec(successCallback, errorCallback, "PhotoAssets", "echoBackHello", [name]);
    }
  };

  function helloTest() {
    var success = function(message) {alert(message);}
    var failure = function() {alert("Error calling Hello Plugin");}
    PhotoAssets.echoBackHello("Cordova World", success, failure);
  }

  document.addEventListener('deviceready', helloTest, false);
})();
