// CFPlugIn factory boilerplate for PurpleMark's Spotlight metadata importer.
// This is Apple's canonical .mdimporter template; the only project-specific
// value is PLUGIN_ID (must match CFPlugInFactories in Info.plist). The actual
// extraction lives in GetMetadataForFile.m.

#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <CoreServices/CoreServices.h>

// Must match the CFPlugInFactories key in Info.plist.
#define PLUGIN_ID "B4D2679F-7825-48AC-901A-DA525770F0D2"

Boolean GetMetadataForFile(void *thisInterface,
                           CFMutableDictionaryRef attributes,
                           CFStringRef contentTypeUTI,
                           CFStringRef pathToFile);

// The layout for an instance of the importer plug-in.
typedef struct __MetadataImporterPluginType {
    MDImporterInterfaceStruct *conduitInterface;
    CFUUIDRef factoryID;
    UInt32 refCount;
} MetadataImporterPluginType;

static MetadataImporterPluginType *AllocMetadataImporterPluginType(CFUUIDRef inFactoryID);
static void DeallocMetadataImporterPluginType(MetadataImporterPluginType *thisInstance);
static HRESULT MetadataImporterQueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv);
static ULONG MetadataImporterPluginAddRef(void *thisInstance);
static ULONG MetadataImporterPluginRelease(void *thisInstance);
void *MetadataImporterPluginFactory(CFAllocatorRef allocator, CFUUIDRef typeID);

// The interface function table.
static MDImporterInterfaceStruct importerInterfaceFtbl = {
    NULL,
    MetadataImporterQueryInterface,
    MetadataImporterPluginAddRef,
    MetadataImporterPluginRelease,
    GetMetadataForFile
};

static MetadataImporterPluginType *AllocMetadataImporterPluginType(CFUUIDRef inFactoryID) {
    MetadataImporterPluginType *theNewInstance =
        (MetadataImporterPluginType *)malloc(sizeof(MetadataImporterPluginType));
    memset(theNewInstance, 0, sizeof(MetadataImporterPluginType));
    theNewInstance->conduitInterface = &importerInterfaceFtbl;
    theNewInstance->factoryID = CFRetain(inFactoryID);
    theNewInstance->refCount = 1;
    return theNewInstance;
}

static void DeallocMetadataImporterPluginType(MetadataImporterPluginType *thisInstance) {
    CFUUIDRef theFactoryID = thisInstance->factoryID;
    free(thisInstance);
    if (theFactoryID) {
        CFPlugInRemoveInstanceForFactory(theFactoryID);
        CFRelease(theFactoryID);
    }
}

static HRESULT MetadataImporterQueryInterface(void *thisInstance, REFIID iid, LPVOID *ppv) {
    CFUUIDRef interfaceID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, iid);
    if (CFEqual(interfaceID, kMDImporterInterfaceID)) {
        ((MetadataImporterPluginType *)thisInstance)->conduitInterface->AddRef(thisInstance);
        *ppv = thisInstance;
        CFRelease(interfaceID);
        return S_OK;
    } else if (CFEqual(interfaceID, IUnknownUUID)) {
        ((MetadataImporterPluginType *)thisInstance)->conduitInterface->AddRef(thisInstance);
        *ppv = thisInstance;
        CFRelease(interfaceID);
        return S_OK;
    }
    *ppv = NULL;
    CFRelease(interfaceID);
    return E_NOINTERFACE;
}

static ULONG MetadataImporterPluginAddRef(void *thisInstance) {
    ((MetadataImporterPluginType *)thisInstance)->refCount += 1;
    return ((MetadataImporterPluginType *)thisInstance)->refCount;
}

static ULONG MetadataImporterPluginRelease(void *thisInstance) {
    ((MetadataImporterPluginType *)thisInstance)->refCount -= 1;
    if (((MetadataImporterPluginType *)thisInstance)->refCount == 0) {
        DeallocMetadataImporterPluginType((MetadataImporterPluginType *)thisInstance);
        return 0;
    }
    return ((MetadataImporterPluginType *)thisInstance)->refCount;
}

void *MetadataImporterPluginFactory(CFAllocatorRef allocator, CFUUIDRef typeID) {
    if (CFEqual(typeID, kMDImporterTypeID)) {
        CFUUIDRef uuid = CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR(PLUGIN_ID));
        MetadataImporterPluginType *result = AllocMetadataImporterPluginType(uuid);
        CFRelease(uuid);
        return result;
    }
    return NULL;
}
