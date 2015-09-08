# cordova_photo_assets
Cordova Plugin for Accessing the Photo Assets on iOS and eventually Android

## Examples

### Simple Example

This example will list the first 100 assets.

```coffeescript

document.addEventListener 'deviceready', ->
  PhotoAssets.setOptions currentCollectionKey: "all", limit: 100, ->
    console.log "all (local) photo assets selected, a photoAssetsChanged event will follow shortly"

document.addEventListener 'photoAssetsChanged', ({details})->
  {assets, currentCollection} = details
  {collectionName} = currentCollection

  console.log "PhotoAssets from Collection: #{collectionName}:"
  for asset in assets
    console.log "  asset #{offset++}: #{asset.assetKey}"
```

### Extended Example

This example shows how to get a list of all available collections, how to follow one specifically, and how to set all custom options.

```coffeescript

document.addEventListener 'deviceready', ->

  PhotoAssets.getCollections (assetCollections)->
    [{
      collectionKey
      collectionName
      estimatedAssetCount
    }] = assetCollections

    PhotoAssets.setOptions
      currentCollectionKey: collectionKey
      thumbnailSize: 270
      limit: 100
      offset: 0
      thumbnailQuality: 95
    , ->
      console.log "selected first asset collection: " + collectionName

document.addEventListener 'photoAssetsChanged', ({details})->
  # see previous example or API doc
```

## PhotoAssets API

#### getCollections
```coffeescript
PhotoAssets.getCollections successCallback, errorCallback

successCallback: (collections) ->
  [{collectionKey, collectionName, estimatedAssetCount}] = collections
```

Returns, via successCallback, an array of collections with the following properties each:

* collectionKey: unique identifier for the collection
  * Used to select the collection you want for thumbnails:
  * Ex: ```PhotoAssets.setOptions currentCollectionKey: collectionKey```
* collectionName: human-readable name for the collection
* estimatedAssetCount: (integer) estimated number of photos in the collection

#### setOptions
```coffeescript
PhotoAssets.setOptions
  # all options and their default values:
  currentCollectionKey: ""    # (string)
  offset:               0     # integer >= 0
  limit:                100   # integer >= 1
  thumbnailSize:        270   # maximum pixel height or width as an integer
  thumbnailQuality:     95    # Jpeg quality as an integer between 0 and 100
, successCallback, errorCallback
```

When setting options, all options are optional. Omitted options will be left untouched from their previous value.

Notes:

* Set ```currentCollectionKey``` to ```"all"``` for all local assets. Set it to ```""``` to stop all asset monitoring. To select specific collections, use ```getCollections``` to get a list of all collections and their respective ```collectionKeys```.
* ```offset``` and ```limit``` define a "window" into the full list of assets for the current selected collection. Thumbnail images are automatically generated for all assets starting at number ```offset``` through asset number ```offset + limit - 1```. Performance test your application to determine the best performing ```limit``` value.

#### getOptions
```coffeescript
PhotoAssets.getOptions successCallback, errorCallback

successCallback: (options) ->
```

Returns, via successCallback, the current value for all options as an ```options``` object.

#### getPhoto

```coffeescript
PhotoAssets.getPhoto
  assetKey:          "string" # required - see photoAssetsChanged
  maxSize:           123      # width and height <= maxSize. default: no max
  quality:           95       # 0 to 100 JPG quality. default: 95
, successCallback, errorCallback

successCallback: ({
  assetKey            # unique key for this asset
  photoUrl            # link to the app-local image file
  pixelWidth          # width of the app-local image file
  pixelHeight         # height of the app-local image file
  originalPixelWidth  # width of the original asset
  originalPixelHeight # height of the original asset
}) ->
```

This call fetches a photo given its ```assetKey```. Asset keys are provided via ```photoAssetsChanged``` events. On success, a version of the photo asset has been writen to app-local storage and is accessable via ```photoUrl```. This temporary file is unique to this call and will stick around until the next time the plugin is initialized - sometime after the next app start.

#### photoAssetsChanged event

```coffeescript
document.addEventListener 'photoAssetsChanged', ({details})->
  {
    options             # same object returned by getOptions
    collections         # same array returned by getCollections
    assets              # array of all assets in the current window with valid thumbnails
    currentCollection   # object describing the current collection
  } = details

  [{
    assetKey            # unique key for this asset
    photoUrl            # url to fetch the thumbnail photo
    pixelWidth          # width of the thumbnail
    pixelHeight         # height of the thumbnail
    originalPixelWidth  # width of the original asset
    originalPixelHeight # height of the original asset
  }] = assets
```

## Notes

### Temporary Files

This plugin creates temporary files in its own temporary folder. Each time the plugin is initialized, it deletes all existing temporary files. Plugin init happens on the first API call.

# Future

```
iOS supports the following additional attributes for some collections:

  startDate
  endDate
  approximateLocation
  localizedLocationNames

And the following additional asset properties:

  location, duration, favorite, hidden
```
