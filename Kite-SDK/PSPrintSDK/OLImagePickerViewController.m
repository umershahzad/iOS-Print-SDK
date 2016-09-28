//
//  Modified MIT License
//
//  Copyright (c) 2010-2016 Kite Tech Ltd. https://www.kite.ly
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The software MAY ONLY be used with the Kite Tech Ltd platform and MAY NOT be modified
//  to be used with any competitor platforms. This means the software MAY NOT be modified
//  to place orders with any competitors to Kite Tech Ltd, all orders MUST go through the
//  Kite Tech Ltd platform servers.
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "OLImagePickerViewController.h"
#import "UIImage+ImageNamedInKiteBundle.h"
#import "OLKiteUtils.h"
#import "OLCustomViewControllerPhotoProvider.h"
#import <Photos/Photos.h>
#import "OLUpsellViewController.h"
#import "NSObject+Utils.h"
#import "OLAnalytics.h"
#import "OLProductPrintJob.h"
#import "OLPrintOrder.h"
#import "OLUserSession.h"
#import "OLAsset+Private.h"
#import "OLImagePickerProviderCollection.h"
#import "OLImagePickerProvider.h"
#import "OLImagePickerLoginPageViewController.h"
#import "OLOAuth2AccountStore.h"
#import "OLKitePrintSDK.h"
#import "UIViewController+OLMethods.h"
#import "OLPaymentViewController.h"
#import "OLFacebookSDKWrapper.h"
#import "OLQRCodeUploadViewController.h"
#import "OLImagePickerPhotosPageViewController.h"
#import "OLCustomPickerController.h"
#import "OLKiteABTesting.h"

@interface OLKiteViewController ()
@property (strong, nonatomic) NSMutableArray <OLCustomViewControllerPhotoProvider *> *customImageProviders;
@end

@interface OLKitePrintSDK ()
+ (NSString *)instagramRedirectURI;
+ (NSString *)instagramSecret;
+ (NSString *)instagramClientID;
@end

@interface OLImagePickerViewController () <UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIPageViewControllerDelegate, UIPageViewControllerDataSource, OLUpsellViewControllerDelegate, OLCustomImagePickerViewControllerDelegate>
@property (weak, nonatomic) IBOutlet UICollectionView *sourcesCollectionView;
@property (weak, nonatomic) IBOutlet UIView *containerView;
@property (strong, nonatomic) UIPageViewController *pageController;
@property (strong, nonatomic) UIVisualEffectView *visualEffectView;
@property (assign, nonatomic) CGSize rotationSize;

@property (strong, nonatomic) NSMutableArray<OLImagePickerProvider *> *providers;

@property (strong, nonatomic) NSArray<OLAsset *> *originalSelectedAssets;
@property (strong, nonatomic) UIView *selectedProviderIndicator;

@property (assign, nonatomic) BOOL viewWillDisappear;
@end

@interface OLProduct ()
@property (strong, nonatomic) NSMutableSet <OLUpsellOffer *>*declinedOffers;
@property (strong, nonatomic) NSMutableSet <OLUpsellOffer *>*acceptedOffers;
@property (strong, nonatomic) OLUpsellOffer *redeemedOffer;
- (BOOL)hasOfferIdBeenUsed:(NSUInteger)identifier;
@end

@interface OLProductPrintJob ()
@property (strong, nonatomic) NSMutableSet <OLUpsellOffer *>*declinedOffers;
@property (strong, nonatomic) NSMutableSet <OLUpsellOffer *>*acceptedOffers;
@property (strong, nonatomic) OLUpsellOffer *redeemedOffer;
@end

@interface OLPrintOrder ()
- (BOOL)hasOfferIdBeenUsed:(NSUInteger)identifier;
@end

@implementation OLImagePickerViewController

@synthesize selectedAssets=_selectedAssets;

- (void)setSelectedAssets:(NSMutableArray<OLAsset *> *)selectedAssets{
    self.originalSelectedAssets = [[NSArray alloc] initWithArray:selectedAssets];
    
    _selectedAssets = selectedAssets;
}

- (NSMutableArray<OLAsset *> *)selectedAssets{
    if (!_selectedAssets){
        return [OLUserSession currentSession].userSelectedPhotos;
    }
    
    return _selectedAssets;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (!self.navigationController){
        [self.nextButton removeFromSuperview];
    }
    else if (self.navigationController.viewControllers.firstObject == self && !self.overrideImagePickerMode){
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(onBarButtonItemCancelTapped:)];
        [self.nextButton removeTarget:self action:@selector(onButtonNextClicked:) forControlEvents:UIControlEventTouchUpInside];
        [self.nextButton addTarget:self action:@selector(onButtonDoneTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.nextButton setTitle:NSLocalizedStringFromTableInBundle(@"Done", @"KitePrintSDK", [OLKiteUtils kiteBundle], @"") forState:UIControlStateNormal];
    }
    else{
        self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Back", @"KitePrintSDK", [OLKiteUtils kiteBundle], @"")
                                                                                 style:UIBarButtonItemStylePlain
                                                                                target:nil
                                                                                action:nil];
    }
    
    if ([OLKiteABTesting sharedInstance].lightThemeColor1){
        self.nextButton.backgroundColor = [OLKiteABTesting sharedInstance].lightThemeColor1;
    }
    
    NSMutableArray<OLImagePickerProvider *> *providers = [[NSMutableArray<OLImagePickerProvider *> alloc] init];
    self.providers = providers;
    [self setupProviders];
    [self updateRecentsWith:[OLUserSession currentSession].recentPhotos];
    
    self.automaticallyAdjustsScrollViewInsets = NO;
        
    self.sourcesCollectionView.delegate = self;
    self.sourcesCollectionView.dataSource = self;
    
    self.pageController = [[UIPageViewController alloc] initWithTransitionStyle:UIPageViewControllerTransitionStyleScroll navigationOrientation:UIPageViewControllerNavigationOrientationHorizontal options:nil];
    self.pageController.delegate = self;
    self.pageController.dataSource = self;
    [self.pageController setViewControllers:@[[self viewControllerAtIndex:0]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:NULL];
    [self addChildViewController:self.pageController];
    [self.containerView addSubview:self.pageController.view];
    
    UIView *view = self.pageController.view;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = NSDictionaryOfVariableBindings(view);
    NSMutableArray *con = [[NSMutableArray alloc] init];
    
    NSArray *visuals = @[@"H:|-0-[view]-0-|",
                         @"V:|-0-[view]-0-|"];
    
    
    for (NSString *visual in visuals) {
        [con addObjectsFromArray: [NSLayoutConstraint constraintsWithVisualFormat:visual options:0 metrics:nil views:views]];
    }
    
    [view.superview addConstraints:con];
    
    UIVisualEffect *blurEffect;
    blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight];
    
    self.visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    view = self.visualEffectView;
    [self.sourcesCollectionView.superview insertSubview:view belowSubview:self.sourcesCollectionView];
    
    view.translatesAutoresizingMaskIntoConstraints = NO;
    views = NSDictionaryOfVariableBindings(view);
    con = [[NSMutableArray alloc] init];
    
    visuals = @[@"H:|-0-[view]-0-|",
                         @"V:|-0-[view]-0-|"];
    
    
    for (NSString *visual in visuals) {
        [con addObjectsFromArray: [NSLayoutConstraint constraintsWithVisualFormat:visual options:0 metrics:nil views:views]];
    }
    
    [view.superview addConstraints:con];
    
    view.clipsToBounds = NO;
    view.layer.shadowColor = [[UIColor blackColor] CGColor];
    view.layer.shadowOpacity = .3;
    view.layer.shadowOffset = CGSizeMake(0, 1);
    view.layer.shadowRadius = 2;
    
    self.selectedProviderIndicator = [[UIView alloc] init];
    self.selectedProviderIndicator.backgroundColor = self.sourcesCollectionView.tintColor;
    
    [self.visualEffectView addSubview:self.selectedProviderIndicator];
    view = self.selectedProviderIndicator;
    
    view.translatesAutoresizingMaskIntoConstraints = NO;
    views = NSDictionaryOfVariableBindings(view);
    con = [[NSMutableArray alloc] init];
    
    CGFloat width = [self collectionView:self.sourcesCollectionView layout:self.sourcesCollectionView.collectionViewLayout sizeForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0]].width;
    
    visuals = @[[NSString stringWithFormat:@"H:|-0-[view(%f)]", width],
                         @"V:[view(1.5)]-0-|"];
    
    
    for (NSString *visual in visuals) {
        [con addObjectsFromArray: [NSLayoutConstraint constraintsWithVisualFormat:visual options:0 metrics:nil views:views]];
    }
    
    [view.superview addConstraints:con];
    
    [self updateTitleBasedOnSelectedPhotoQuanitity];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    
    self.viewWillDisappear = NO;
    
    if ([self.presentingViewController respondsToSelector:@selector(viewControllers)]) {
        UIViewController *presentingVc = [(UINavigationController *)self.presentingViewController viewControllers].lastObject;
        if (![presentingVc isKindOfClass:[OLPaymentViewController class]]){
            [self addBasketIconToTopRight];
        }
    }
    else{
        [self addBasketIconToTopRight];
    }
    
    [self positionSelectedProviderIndicator];
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    
    self.viewWillDisappear = YES;
}

- (void)setupLibraryProviderAtIndex:(NSInteger)index{
    if (![OLKiteUtils cameraRollEnabled:self]){
        return;
    }
    
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.wantsIncrementalChangeDetails = NO;
    options.includeHiddenAssets = NO;
    options.includeAllBurstAssets = NO;
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    if ([options respondsToSelector:@selector(setIncludeAssetSourceTypes:)]){
        options.includeAssetSourceTypes = PHAssetSourceTypeCloudShared | PHAssetSourceTypeUserLibrary | PHAssetSourceTypeiTunesSynced;
    }
    options.predicate = [NSPredicate predicateWithFormat:@"mediaType = %d",PHAssetMediaTypeImage];
    
    PHAssetCollection *userLibraryCollection = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:nil].firstObject;
    PHFetchResult *fetchedPhotos = [PHAsset fetchAssetsInAssetCollection:userLibraryCollection options:options];
    OLImagePickerProviderCollection *userLibraryProviderCollection = [[OLImagePickerProviderCollection alloc] initWithPHFetchResult:fetchedPhotos name:userLibraryCollection.localizedTitle];
    
    OLImagePickerProvider *provider = [[OLImagePickerProvider alloc] initWithCollections:@[userLibraryProviderCollection] name:NSLocalizedString(@"Photo Library", @"") icon:[UIImage imageNamedInKiteBundle:@"import_gallery"]];
    provider.providerType = OLImagePickerProviderTypePhotoLibrary;
    [(NSMutableArray *)self.providers insertObject:provider atIndex:index];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *assetCollections = [[NSMutableArray alloc] init];
        PHFetchResult *result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumFavorites options:nil];
        for (PHAssetCollection *collection in result){
            [assetCollections addObject:collection];
        }
        result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumSelfPortraits options:nil];
        for (PHAssetCollection *collection in result){
            [assetCollections addObject:collection];
        }
        result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumRecentlyAdded options:nil];
        for (PHAssetCollection *collection in result){
            [assetCollections addObject:collection];
        }
        result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumPanoramas options:nil];
        for (PHAssetCollection *collection in result){
            [assetCollections addObject:collection];
        }
        result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumScreenshots options:nil];
        for (PHAssetCollection *collection in result){
            [assetCollections addObject:collection];
        }
        result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
        for (PHAssetCollection *collection in result){
            [assetCollections addObject:collection];
        }
        
        NSMutableArray<OLImagePickerProviderCollection *> *collections = [[NSMutableArray alloc] init];
        for (PHAssetCollection *fetchedCollection in assetCollections){
            PHFetchResult *fetchedPhotos = [PHAsset fetchAssetsInAssetCollection:fetchedCollection options:options];
            if (fetchedPhotos.count == 0){
                continue;
            }
            OLImagePickerProviderCollection *collection = [[OLImagePickerProviderCollection alloc] initWithPHFetchResult:fetchedPhotos name:fetchedCollection.localizedTitle];
            [collections addObject:collection];
        }
        
        [provider.collections addObjectsFromArray:collections];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.pageController.viewControllers.firstObject isKindOfClass:[OLImagePickerPhotosPageViewController class]]){
                [[self.pageController.viewControllers.firstObject albumsCollectionView] reloadData];
            }
        });
    });
    
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined){
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status){
            if (status == PHAuthorizationStatusAuthorized){
                for (OLImagePickerProvider *provider in self.providers){
                    if (provider.providerType == OLImagePickerProviderTypePhotoLibrary){
                        NSInteger providerIndex = [self.providers indexOfObjectIdenticalTo:provider];
                        [self.providers removeObjectAtIndex:providerIndex];
                        [self setupLibraryProviderAtIndex:providerIndex];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self reloadPageController];
                        });
                        break;
                    }
                }
            }
        }];
    }
}

- (void)setupRecentsProvider{
    if ([OLUserSession currentSession].appAssets.count == 0 && [OLUserSession currentSession].recentPhotos.count == 0){
        return;
    }
    
    OLImagePickerProviderCollection *collection = [[OLImagePickerProviderCollection alloc] initWithArray:[OLUserSession currentSession].appAssets name:NSLocalizedString(@"All Photos", @"")];
    
    OLImagePickerProvider *provider = [[OLImagePickerProvider alloc] initWithCollections:@[collection] name:NSLocalizedStringFromTableInBundle(@"Recents", @"KitePrintSDK", [OLKiteUtils kiteBundle], @"") icon:[UIImage imageNamedInKiteBundle:@"bookmark"]];
    provider.providerType = OLImagePickerProviderTypeRecents;
    [self.providers addObject:provider];
}

- (void)setupFacebookProvider{
    if (![OLKiteUtils facebookEnabled]){
        return;
    }
    OLImagePickerProvider *provider = [[OLImagePickerProvider alloc] initWithCollections:[@[] mutableCopy] name:@"Facebook" icon:[UIImage imageNamedInKiteBundle:@"import_facebook"]];
    provider.providerType = OLImagePickerProviderTypeFacebook;
    [self.providers addObject:provider];
}

- (void)setupInstagramProvider{
    if (![OLKiteUtils instagramEnabled]){
        return;
    }
    OLImagePickerProvider *provider = [[OLImagePickerProvider alloc] initWithCollections:[@[] mutableCopy] name:@"Instagram" icon:[UIImage imageNamedInKiteBundle:@"import_instagram"]];
    provider.providerType = OLImagePickerProviderTypeInstagram;
    [self.providers addObject:provider];
}

- (void)setupCustomProviders{
    for (OLImagePickerProvider *customProvider in [OLUserSession currentSession].kiteVc.customImageProviders){
        if ([customProvider isKindOfClass:[OLCustomViewControllerPhotoProvider class]]){
            customProvider.providerType = OLImagePickerProviderTypeViewController;
            [self.providers addObject:customProvider];
        }
        else{
            NSMutableArray *collections = [[NSMutableArray alloc] init];
            for (OLImagePickerProviderCollection *collection in customProvider.collections){
                NSMutableArray *assets = [[NSMutableArray alloc] init];
                for (OLAsset *asset in collection){
                    [assets addObject:asset];
                }
                
                [collections addObject:[[OLImagePickerProviderCollection alloc] initWithArray:assets name:collection.name]];
            }
            OLImagePickerProvider *provider = [[OLImagePickerProvider alloc] initWithCollections:collections name:customProvider.name icon:customProvider.icon];
            provider.providerType = OLImagePickerProviderTypeCustom;
            [self.providers addObject:provider];
        }
    }
}

- (void)setupQRCodeProvider{
    if ([OLKiteUtils qrCodeUploadEnabled]){
        OLImagePickerProviderCollection *emptyCollection = [[OLImagePickerProviderCollection alloc] initWithArray:@[] name:@"QR Code Upload"];
        OLImagePickerProvider *provider = [[OLImagePickerProvider alloc] initWithCollections:@[emptyCollection] name:NSLocalizedStringFromTableInBundle(@"Your Phone", @"KitePrintSDK", [OLKiteUtils kiteBundle], @"") icon:[UIImage imageNamedInKiteBundle:@"case-options"]];
        provider.providerType = OLImagePickerProviderTypeQRCode;
        [self.providers addObject:provider];
    }
}

- (void)setupProviders{
    [self setupRecentsProvider];
    [self setupLibraryProviderAtIndex:self.providers.count];
    [self setupFacebookProvider];
    [self setupInstagramProvider];
    [self setupCustomProviders];
    [self setupQRCodeProvider];
}

- (void)updateTopConForVc:(UIViewController *)vc{
    if ([vc isKindOfClass:[OLImagePickerPhotosPageViewController class]]){
        if (self.viewWillDisappear && !self.navigationController){
            return;
        }
        ((OLImagePickerPhotosPageViewController *)vc).albumLabelContainerTopCon.constant = [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height + self.sourcesCollectionView.frame.size.height;
        
        CGFloat offset = [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height + self.sourcesCollectionView.frame.size.height + ((OLImagePickerPhotosPageViewController *)vc).albumLabelContainer.frame.size.height;
        ((OLImagePickerPhotosPageViewController *)vc).collectionView.contentInset = UIEdgeInsetsMake(offset, 0, 70, 0);
        ((OLImagePickerPhotosPageViewController *)vc).collectionView.contentOffset = CGPointMake(0, -offset);
        ((OLImagePickerPhotosPageViewController *)vc).albumsContainerHeight.constant = self.view.frame.size.height;
    }
    else{
        ((OLImagePickerPhotosPageViewController *)vc).albumLabelContainerTopCon.constant = [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height + 10;
    }
}

- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    
    [self updateTopConForVc:self.pageController.viewControllers.firstObject];
    [self positionSelectedProviderIndicator];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    self.rotationSize = size;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinator> context){
        [self.sourcesCollectionView.collectionViewLayout invalidateLayout];
        self.selectedProviderIndicator.alpha = 0;
    }completion:^(id<UIViewControllerTransitionCoordinator> context){
        [self.sourcesCollectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:[self.pageController.viewControllers.firstObject pageIndex] inSection:0] atScrollPosition:UICollectionViewScrollPositionNone animated:YES];
        [self positionSelectedProviderIndicator];
        [UIView animateWithDuration:0.25 animations:^{
            self.selectedProviderIndicator.alpha = 1;
        }];
    }];
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView{
    OLImagePickerPhotosPageViewController *vc = self.pageController.viewControllers.firstObject;
    if ([vc isKindOfClass:[OLImagePickerPhotosPageViewController class]]){
        [[vc collectionView] scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:0] atScrollPosition:UICollectionViewScrollPositionTop animated:YES];
    }
    
    return YES;
}

#pragma mark Asset Management

- (void)updateTitleBasedOnSelectedPhotoQuanitity {
    if (self.selectedAssets.count == 0) {
        self.title = NSLocalizedString(@"Choose Photos", @"");
    } else {
        if (self.product.quantityToFulfillOrder > 1){
            NSUInteger numOrders = 1 + (MAX(0, self.selectedAssets.count - 1 + [self totalNumberOfExtras]) / self.product.quantityToFulfillOrder);
            NSUInteger quanityToFulfilOrder = numOrders * self.product.quantityToFulfillOrder;
            self.title = [NSString stringWithFormat:@"%lu / %lu", (unsigned long)self.selectedAssets.count + [self totalNumberOfExtras], (unsigned long)quanityToFulfilOrder];
        }
        else{
            self.title = [NSString stringWithFormat:@"%lu", (unsigned long)self.selectedAssets.count];
        }
    }
}

-(NSUInteger) totalNumberOfExtras{
    if (self.product.productTemplate.templateUI == kOLTemplateUIFrame || self.product.productTemplate.templateUI == kOLTemplateUIPoster || self.product.productTemplate.templateUI == kOLTemplateUIPhotobook){
        return 0;
    }
    
    NSUInteger res = 0;
    for (OLAsset *photo in self.selectedAssets){
        res += photo.extraCopies;
    }
    return res;
}

#pragma mark PageViewController

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerAfterViewController:(UIViewController *)viewController{
    return [self viewControllerAtIndex:[(OLImagePickerPhotosPageViewController *)viewController pageIndex] + 1];
}

- (UIViewController *)pageViewController:(UIPageViewController *)pageViewController viewControllerBeforeViewController:(UIViewController *)viewController{
    return [self viewControllerAtIndex:[(OLImagePickerPhotosPageViewController *)viewController pageIndex] - 1];
}

- (void)reloadPageController{
    [self.pageController setViewControllers:@[[self viewControllerAtIndex:[self.pageController.viewControllers.firstObject pageIndex]]] direction:UIPageViewControllerNavigationDirectionForward animated:NO completion:NULL];
}

- (UIViewController *)viewControllerAtIndex:(NSInteger)index{
    if(index < 0 || index >= self.providers.count){
        return nil;
    }
    
    if (self.providers[index].providerType == OLImagePickerProviderTypeInstagram){
        [[OLOAuth2AccountStore sharedStore] setClientID:[OLKitePrintSDK instagramClientID]
                                                 secret:[OLKitePrintSDK instagramSecret]
                                       authorizationURL:[NSURL URLWithString:@"https://api.instagram.com/oauth/authorize"]
                                               tokenURL:[NSURL URLWithString:@"https://api.instagram.com/oauth/access_token/"]
                                            redirectURL:[NSURL URLWithString:[OLKitePrintSDK instagramRedirectURI]]
                                         forAccountType:@"instagram"];
    }
    
    OLImagePickerPageViewController *vc;
    
    if (self.providers[index].providerType == OLImagePickerProviderTypeFacebook && ![OLFacebookSDKWrapper currentAccessToken]){
        vc = [self.storyboard instantiateViewControllerWithIdentifier:@"OLImagePickerLoginPageViewController"];
        vc.pageIndex = index;
    }
    else if (self.providers[index].providerType == OLImagePickerProviderTypeInstagram && [[OLOAuth2AccountStore sharedStore] accountsWithAccountType:@"instagram"].count == 0){
        vc = [self.storyboard instantiateViewControllerWithIdentifier:@"OLImagePickerLoginPageViewController"];
        vc.pageIndex = index;
    }
    else if (self.providers[index].providerType == OLImagePickerProviderTypePhotoLibrary && [PHPhotoLibrary authorizationStatus] != PHAuthorizationStatusAuthorized){
        vc = [self.storyboard instantiateViewControllerWithIdentifier:@"OLImagePickerLoginPageViewController"];
        vc.pageIndex = index;
    }
    else{
        vc = [self.storyboard instantiateViewControllerWithIdentifier:@"OLImagePickerPhotosPageViewController"];
        vc.pageIndex = index;
        ((OLImagePickerPhotosPageViewController *)vc).quantityPerItem = self.product.quantityToFulfillOrder;
    }
    vc.imagePicker = self;
    vc.provider = self.providers[index];
    [vc.view class]; //force view did load
    [self updateTopConForVc:vc];
    
    return vc;
}

- (void)presentExternalViewControllerForProvider:(OLImagePickerProvider *)provider{
    if (provider.providerType == OLImagePickerProviderTypeQRCode){
        OLQRCodeUploadViewController *vc = (OLQRCodeUploadViewController *) [[UIStoryboard storyboardWithName:@"OLKiteStoryboard" bundle:[OLKiteUtils kiteBundle]] instantiateViewControllerWithIdentifier:@"OLQRCodeUploadViewController"];
        vc.modalPresentationStyle = UIModalPresentationFormSheet;
        vc.delegate = self;
        vc.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(assetsPickerControllerDidCancel:)];
        OLNavigationController *nvc = [[OLNavigationController alloc] initWithRootViewController:vc];
        [self presentViewController:nvc animated:YES completion:nil];
        
        self.providerForPresentedVc = provider;
    }
    else if (provider.providerType == OLImagePickerProviderTypeViewController && [provider isKindOfClass:[OLCustomViewControllerPhotoProvider class]]){
        UIViewController *vc = [(OLCustomViewControllerPhotoProvider *)provider vc];
        ((id<OLCustomPickerController>)vc).delegate = self;
        [self presentViewController:vc animated:YES completion:nil];
        self.providerForPresentedVc = provider;
    }
}

- (void)assetsPickerControllerDidCancel:(UIViewController *)picker{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)assetsPickerController:(UIViewController *)picker didFinishPickingAssets:(NSArray<OLAsset *> *)assets{
    //Check that the objects are OLAssets
    NSMutableArray *validAssets = [[NSMutableArray alloc] initWithArray:assets];
    for (id obj in assets){
        if (![obj isKindOfClass:[OLAsset class]]){
            [validAssets removeObjectIdenticalTo:obj];
        }
    }
    
    [self.providerForPresentedVc.collections.firstObject addAssets:validAssets unique:YES];
    for (OLAsset *asset in validAssets){
        if(self.maximumPhotos == 0 || self.selectedAssets.count < self.maximumPhotos){
            [self.selectedAssets addObject:asset];
        }
    }
    [self reloadPageController];
    [picker dismissViewControllerAnimated:YES completion:NULL];
}

- (void)pageViewController:(UIPageViewController *)pageViewController didFinishAnimating:(BOOL)finished previousViewControllers:(NSArray<UIViewController *> *)previousViewControllers transitionCompleted:(BOOL)completed{
    [self.sourcesCollectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:[pageViewController.viewControllers.firstObject pageIndex] inSection:0] atScrollPosition:UICollectionViewScrollPositionNone animated:YES];
    self.nextButton.hidden = NO;
    ((OLImagePickerPageViewController *)(self.pageController.viewControllers.firstObject)).nextButton.hidden = YES;
    [self positionSelectedProviderIndicator];
}

#pragma mark CollectionView

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath{
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"sourceCell" forIndexPath:indexPath];
    
    UIImageView *imageView = [cell viewWithTag:10];
    UILabel *label = [cell viewWithTag:20];
    imageView.image = self.providers[indexPath.item].icon;
    label.text = self.providers[indexPath.item].name;
    
    return cell;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{
    return self.providers.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(95, collectionView.frame.size.height);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section{
    
    CGFloat margin = MAX((collectionView.frame.size.width - ([self collectionView:collectionView layout:collectionView.collectionViewLayout sizeForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]].width * [self collectionView:collectionView numberOfItemsInSection:section] + [self collectionView:collectionView layout:collectionViewLayout minimumLineSpacingForSectionAtIndex:section] * ([self collectionView:collectionView numberOfItemsInSection:section]-1)))/2.0, 5);
    return UIEdgeInsetsMake(0, margin, 0, margin);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section{
    return 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section{
    return 0;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath{
    NSInteger currentPageIndex = [self.pageController.viewControllers.firstObject pageIndex];
    UIViewController *showingVc = self.pageController.viewControllers.firstObject;
    if (currentPageIndex == indexPath.item){
        if ([showingVc isKindOfClass:[OLImagePickerPhotosPageViewController class]]){
            [(OLImagePickerPhotosPageViewController *)showingVc closeAlbumsDrawer];
        }
        return;
    }
    
    UIViewController *vc = [self viewControllerAtIndex:indexPath.item];
    
    [self.pageController setViewControllers:@[vc] direction:currentPageIndex < indexPath.item ? UIPageViewControllerNavigationDirectionForward : UIPageViewControllerNavigationDirectionReverse animated:YES completion:NULL];
    
    [self positionSelectedProviderIndicator];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
    [self positionSelectedProviderIndicator];
}

- (void)positionSelectedProviderIndicator{
    UICollectionViewCell *cell = [self.sourcesCollectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:[self.pageController.viewControllers.firstObject pageIndex] inSection:0]];
    
    if (cell){
        self.selectedProviderIndicator.alpha = 1;
        self.selectedProviderIndicator.transform = CGAffineTransformMakeTranslation([self.sourcesCollectionView convertRect:cell.frame toView:self.view].origin.x, 0);
    }
    else{
        self.selectedProviderIndicator.alpha = 0;
    }
}

#pragma mark Navigation

- (BOOL)shouldGoToOrderPreview {
    if (self.selectedAssets.count == 0) {
        UIAlertController *av = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Oops!", @"") message:NSLocalizedString(@"Please select some images to print first.", @"") preferredStyle:UIAlertControllerStyleAlert];
        [av addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"") style:UIAlertActionStyleDefault handler:NULL]];
        [self presentViewController:av animated:YES completion:NULL];
        return NO;
    }
    
    return YES;
}

- (void)updateRecentsWith:(NSArray *)assets{
    for (OLAsset *asset in assets){
        if (![[OLUserSession currentSession].recentPhotos containsObject:asset]){
            [[OLUserSession currentSession].recentPhotos addObject:asset];
        }
    }
    
    for (OLImagePickerProvider *provider in self.providers){
        if (provider.providerType == OLImagePickerProviderTypeRecents){
            [provider.collections.firstObject addAssets:[OLUserSession currentSession].recentPhotos unique:YES];
        }
    }
}

- (IBAction)onButtonNextClicked:(UIButton *)sender {
    if ([self shouldGoToOrderPreview]) {
        [self updateRecentsWith:[OLUserSession currentSession].userSelectedPhotos];
        
        OLUpsellOffer *offer = [self upsellOfferToShow];
        BOOL shouldShowOffer = offer != nil;
        if (offer){
            shouldShowOffer &= offer.minUnits <= self.selectedAssets.count;
            shouldShowOffer &= offer.maxUnits == 0 || offer.maxUnits >= self.selectedAssets.count;
            shouldShowOffer &= [OLProduct productWithTemplateId:offer.offerTemplate] != nil;
        }
        
        [OLAnalytics trackUpsellShown:shouldShowOffer];
        if (shouldShowOffer){
            OLUpsellViewController *c = [self.storyboard instantiateViewControllerWithIdentifier:@"OLUpsellViewController"];
            c.providesPresentationContextTransitionStyle = true;
            c.definesPresentationContext = true;
            c.modalPresentationStyle = UIModalPresentationOverCurrentContext;
            c.delegate = self;
            c.offer = offer;
            c.triggeredProduct = self.product;
            [self presentViewController:c animated:NO completion:NULL];
        }
        else{
            [self showOrderPreview];
        }
    }
}

-(void)showOrderPreview{
    UIViewController* orvc = [self.storyboard instantiateViewControllerWithIdentifier:[OLKiteUtils reviewViewControllerIdentifierForProduct:self.product photoSelectionScreen:NO]];
    
    [orvc safePerformSelector:@selector(setProduct:) withObject:self.product];
    [self.navigationController pushViewController:orvc animated:YES];
}

- (void)onBarButtonItemCancelTapped:(UIBarButtonItem *)sender{
    [self.selectedAssets removeAllObjects];
    [self.selectedAssets addObjectsFromArray:self.originalSelectedAssets];
    
    if ([self.delegate respondsToSelector:@selector(imagePickerDidCancel:)]){
        [self.delegate imagePickerDidCancel:self];
    }
    else{
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
}

- (void)onButtonDoneTapped:(UIButton *)sender{
    NSMutableArray *removedAssets = [[NSMutableArray alloc] initWithArray:self.originalSelectedAssets];
    [removedAssets removeObjectsInArray:self.selectedAssets];
    
    NSMutableArray *addedAssets = [[NSMutableArray alloc] initWithArray:self.selectedAssets];
    [addedAssets removeObjectsInArray:self.originalSelectedAssets];
    
    [self updateRecentsWith:addedAssets];
    
    if ([self.delegate respondsToSelector:@selector(imagePicker:didFinishPickingAssets:added:removed:)]){
        [self.delegate imagePicker:self didFinishPickingAssets:self.selectedAssets added:addedAssets removed:removedAssets];
    }
    else{
        [self dismissViewControllerAnimated:YES completion:NULL];
    }
}

#pragma mark Upsells

- (OLUpsellOffer *)upsellOfferToShow{
    if (/* DISABLES CODE */ (YES)){
        return nil;// Need to test first
    }
    NSArray *upsells = self.product.productTemplate.upsellOffers;
    if (upsells.count == 0){
        return nil;
    }
    
    OLUpsellOffer *offerToShow;
    for (OLUpsellOffer *offer in upsells){
        //Check if offer is valid for this point
        if (offer.active && offer.type == OLUpsellOfferTypeItemAdd){
            
            if ([self.product hasOfferIdBeenUsed:offer.identifier]){
                continue;
            }
            if ([[OLUserSession currentSession].printOrder hasOfferIdBeenUsed:offer.identifier]){
                continue;
            }
            
            //Find the max priority offer
            if (!offerToShow || offerToShow.priority < offer.priority){
                offerToShow = offer;
            }
        }
    }
    
    return offerToShow;
}

- (void)userDidDeclineUpsell:(OLUpsellViewController *)vc{
    [self.product.declinedOffers addObject:vc.offer];
    [vc dismissViewControllerAnimated:NO completion:^{
        [self showOrderPreview];
    }];
}

- (void)userDidAcceptUpsell:(OLUpsellViewController *)vc{
    [self.product.acceptedOffers addObject:vc.offer];
    [vc dismissViewControllerAnimated:NO completion:^{
        if (vc.offer.prepopulatePhotos){
            id<OLPrintJob> job = [self addItemToBasketWithTemplateId:vc.offer.offerTemplate];
            [(OLProductPrintJob *)job setRedeemedOffer:vc.offer];
            [self showOrderPreview];
        }
        else if ([self.product.templateId isEqualToString:vc.offer.offerTemplate]){
            self.product.redeemedOffer = vc.offer;
        }
        else{
            id<OLPrintJob> job = [self addItemToBasketWithTemplateId:self.product.templateId];
            [[(OLProductPrintJob *)job acceptedOffers] addObject:vc.offer];
            
            OLProduct *offerProduct = [OLProduct productWithTemplateId:vc.offer.offerTemplate];
            UIViewController *nextVc = [self.storyboard instantiateViewControllerWithIdentifier:[OLKiteUtils reviewViewControllerIdentifierForProduct:offerProduct photoSelectionScreen:[OLKiteUtils imageProvidersAvailable:self]]];
            [nextVc safePerformSelector:@selector(setProduct:) withObject:offerProduct];
            NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
            [stack removeObject:self];
            [stack addObject:nextVc];
            [self.navigationController setViewControllers:stack animated:YES];
        }
    }];
}

- (id<OLPrintJob>)addItemToBasketWithTemplateId:(NSString *)templateId{
    OLProduct *offerProduct = [OLProduct productWithTemplateId:templateId];
    NSMutableArray *assets = [[NSMutableArray alloc] init];
    if (offerProduct.productTemplate.templateUI == kOLTemplateUINonCustomizable){
        //Do nothing, no assets needed
    }
    else if (offerProduct.quantityToFulfillOrder == 1){
        [assets addObject:[self.selectedAssets.firstObject copy]];
    }
    else{
        for (OLAsset *photo in self.selectedAssets){
            [assets addObject:[photo copy]];
        }
    }
    
    id<OLPrintJob> job;
    if ([OLProductTemplate templateWithId:templateId].templateUI == kOLTemplateUIPhotobook){
        job = [OLPrintJob photobookWithTemplateId:templateId OLAssets:assets frontCoverOLAsset:nil backCoverOLAsset:nil];
    }
    else{
        job = [OLPrintJob printJobWithTemplateId:templateId OLAssets:assets];
    }
    
    [[OLUserSession currentSession].printOrder addPrintJob:job];
    return job;
}

@end
