# cordova_photo_assets
Cordova Plugin for Accessing the Photo Assets on iOS and eventually Android

## API

### Simple Example

This example will list all assets for the first asset-collection found.

```coffeescript

document.addEventListener 'deviceready', ->
  PhotoAssets.setOptions currentAssetCollection: "all", ->
    console.log "all (local) photo assets selected, a photoAssetsChanged event will follow shortly"

document.addEventListener 'photoAssetsChanged', ({details})->
  {collection, offset, limit, assets} = details
  {collectionName} = collection

  console.log "#{collectionName} assets: #{offset} to #{offset + assets.length - 1}:"
  for asset in assets
    console.log "  asset #{offset++}: #{asset.assetKey}"
```

### Extended Example

This example shows how to get a list of all available collections, how to follow one specifically, and how to set all custom options.

```coffeescript

document.addEventListener 'deviceready', ->

  PhotoAssets.getAssetCollections (assetCollections)->
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
  {collection, offset, limit, assets} = details
  {collectionName} = collection

  console.log "#{collectionName} assets: #{offset} to #{offset + assets.length - 1}:"
  for asset in assets
    console.log "  asset #{offset++}: #{asset.assetKey}"
```

### PhotoAssets API DETAILS

#### getAssetCollections
```coffeescript
PhotoAssets.getAssetCollections successCallback, errorCallback

successCallback: (collections) ->
  firstCollection = collections[0]
  {collectionKey, collectionName, estimatedAssetCount} = firstCollection
```

On success, the following is invoked:

```coffeescript
  successCallback [
    # one or more collections with the following format:
    {
      collectionKey:        "all"
      collectionName:       "Camera Roll"
      estimatedAssetCount:  2000
    }
  ]
```

#### setOptions
```coffeescript
PhotoAssets.setOptions options, successCallback, errorCallback

successCallback: ->
```

```options``` can be 0, 1 or more of the following. The missing options will not be changed.

* thumbnailSize:        (pixels)
* thumbnailQuality:     (0-100)
* limit:                (int >= 1) number of thumbnails to return starting from the current offset.
* offset:               (int >= 0) current thumbnail offset
* currentCollectionKey: (string) Use "all" for all local images. Otherwise, get collection keys from getAssetCollections


#### getOptions
```coffeescript
PhotoAssets.getOptions successCallback, errorCallback

successCallback: (options) ->
```

Returns the current value for all options as an ```options``` object.

#### getPhoto

```coffeescript
PhotoAssets.getPhoto options, successCallback, errorCallback

successCallback: ({
  photoUrl,
  pixelWidth,
  pixelHeight,
  originalPixelWidth,
  originalPixelHeight
}) ->
```

Options:

* assetKey:           (required) the key of the asset you want the photo for
* maxSize:            (pixels)
* temporaryFilename:  If the name is the same as a previous call, the previous image is overwritten. This is handy so you don't end up with lots of temporary files wasting the users's storage.

#### photoAssetsChanged event

```coffeescript
document.addEventListener 'photoAssetsChanged', ({details})->
  {collection, offset, limit, assets} = details
  {collectionKey, collectionName, estimatedAssetCount} = collection

  firstAsset = assets[0]
  {
    assetKey
    thumbnailUrl
    thumbnailPixelWidth
    thumbnailPixelHeight
    originalPixelWidth
    originalPixelHeight
    mediaType
    creationDate
    modificationDate
  } = firstAsset
```

The event object's ```details```:

* collection: information about the current collection in the same format as returned by ```PhotoAssets.getCollections```
* offset: the current offset for the data-window
* limit: the current size of the data-window
* assets: an array of assets <= limit in length

The asset objects have the following fields:

* assetKey: unique identifier for the asset. Required for ```PhotoAssets.getPhoto```.
* thumbnailUrl: the URL of the immediately-available copy of the thumbnail for this asset
* thumbnailPixelWidth, thumbnailPixelHeight: size of the thumbnail image
* originalPixelWidth, originalPixelHeight: size of the original image
* mediaType: ???
* creationDate: string
* modificationDate: string

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
