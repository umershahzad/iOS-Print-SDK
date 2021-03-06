//
//  Modified MIT License
//
//  Copyright (c) 2010-2017 Kite Tech Ltd. https://www.kite.ly
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

#import "OLCheckoutViewController.h"
#import "OLPaymentViewController.h"
#import "OLPrintOrder.h"
#import "OLAddressPickerController.h"
#import "OLAddress.h"
#import "OLProductTemplate.h"
#import "OLKitePrintSDK.h"
#import "OLAnalytics.h"
#import "OLAddressEditViewController.h"
#import "OLProductPrintJob.h"
#import "OLKiteABTesting.h"
#import "UIImage+OLUtils.h"
#import "UIImage+ImageNamedInKiteBundle.h"
#import "OLKiteUtils.h"
#import "OLImageDownloader.h"
#import "OLUserSession.h"

NSString *const kOLNotificationUserSuppliedShippingDetails = @"co.oceanlabs.pssdk.kOLNotificationUserSuppliedShippingDetails";
NSString *const kOLNotificationUserCompletedPayment = @"co.oceanlabs.pssdk.kOLNotificationUserCompletedPayment";
NSString *const kOLNotificationPrintOrderSubmission = @"co.oceanlabs.pssdk.kOLNotificationPrintOrderSubmission";

NSString *const kOLKeyUserInfoPrintOrder = @"co.oceanlabs.pssdk.kOLKeyUserInfoPrintOrder";

static const NSUInteger kMinPhoneNumberLength = 5;

static const NSUInteger kSectionDeliveryDetails = 0;
static const NSUInteger kSectionEmailAddress = 1;
static const NSUInteger kSectionPhoneNumber = 2;

static const NSUInteger kSectionCount = 3;

static NSString *const kKeyEmailAddress = @"co.oceanlabs.pssdk.kKeyEmailAddress";
static NSString *const kKeyPhone = @"co.oceanlabs.pssdk.kKeyPhone";

@interface OLPaymentViewController (Private)
@property (nonatomic, assign) BOOL presentedModally;
@end

@interface OLPrintOrder (PrivateMethods)
@property (assign, nonatomic) BOOL optOutOfEmail;
@end

@interface OLKiteViewController ()
- (void)setLastTouchDate:(NSDate *)date forViewController:(UIViewController *)vc;
@end

#define kColourLightBlue [UIColor colorWithRed:0 / 255.0 green:122 / 255.0 blue:255 / 255.0 alpha:1.0]

@interface OLCheckoutViewController () <OLAddressPickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate>
@property (strong, nonatomic) UITextField *textFieldEmail, *textFieldPhone;
@property (strong, nonatomic) OLPrintOrder *printOrder;
@property (assign, nonatomic) BOOL presentedModally;
@property (strong, nonatomic) UILabel *kiteLabel;
@property (strong, nonatomic) NSLayoutConstraint *kiteLabelYCon;
@property (weak, nonatomic) UITextField *activeTextView;
@end

@implementation OLCheckoutViewController

- (id)init {
    //NSAssert(NO, @"init is not a valid initializer for OLCheckoutViewController. Use initWithAPIKey:environment:printOrder:, or initWithPrintOrder: instead");
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
    }
    return self;
}

- (id)initWithAPIKey:(NSString *)apiKey environment:(OLKitePrintSDKEnvironment)env printOrder:(OLPrintOrder *)printOrder {
    //NSAssert(printOrder != nil, @"OLCheckoutViewController requires a non-nil print order");
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
        [OLKitePrintSDK setAPIKey:apiKey withEnvironment:env];
        self.printOrder = printOrder;
        //[self.printOrder preemptAssetUpload];
    }
    
    return self;
}

- (id)initWithPrintOrder:(OLPrintOrder *)printOrder {
    //NSAssert(printOrder != nil, @"OLCheckoutViewController requires a non-nil print order");
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
        self.printOrder = printOrder;
        //[self.printOrder preemptAssetUpload];
    }
    
    return self;
}

- (void)presentViewControllerFrom:(UIViewController *)presentingViewController animated:(BOOL)animated completion:(void (^)(void))completion {
    UINavigationController *navController = [[OLNavigationController alloc] initWithRootViewController:self];
    navController.modalPresentationStyle = [OLUserSession currentSession].kiteVc.modalPresentationStyle;
    [presentingViewController presentViewController:navController animated:animated completion:completion];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (![self.parentViewController isKindOfClass:[UINavigationController class]]) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Oops!", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") message:@"OLCheckoutViewController should be part of a UINavigationController stack. Either push the OLCheckoutViewController onto a stack (or make it the rootViewController) or present it modally with OLCheckoutViewController.presentViewControllerFrom:animated:completion:" preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"Acknowledgent to an alert dialog.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){}]];
        [self presentViewController:ac animated:YES completion:NULL];
        
        return;
    }
    
    if (self.printOrder == nil) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Oops!", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") message:@"OLCheckoutViewController printOrder is nil. Did you use the correct initializer (initWithAPIKey:environment:printOrder:, or initWithPrintOrder:). Nothing will work as you expect until you resolve the issue in code." preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"Acknowledgent to an alert dialog.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){}]];
        [self presentViewController:ac animated:YES completion:NULL];
        return;
    }
    
    if ([OLKitePrintSDK apiKey] == nil) {
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Oops!", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") message:@"It appears you have not specified your Kite API Key. Did you use the correct initializer for OLCheckoutViewController (initWithAPIKey:environment:printOrder:) or alternatively  directly set it using OLKitePrintSDK.setAPIKey:withEnvironment:. Nothing will work as you expect until you resolve the issue in code." preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"Acknowledgent to an alert dialog.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){}]];
        [self presentViewController:ac animated:YES completion:NULL];
        return;
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinator> context){
        [self positionKiteLabel];
    } completion:^(id<UIViewControllerTransitionCoordinator> context){
    }];
}

- (CGFloat)edgeInsetTop{
    return self.navigationController.navigationBar.translucent ? [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height : 0;
}



- (void)viewDidLoad {
    [super viewDidLoad];
        
    [self trackViewed];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Next", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") style:UIBarButtonItemStylePlain target:self action:@selector(onButtonNextClicked)];
    UIColor *color1 = [OLKiteABTesting sharedInstance].lightThemeColor1;
    if (color1){
        self.navigationItem.rightBarButtonItem.tintColor = color1;
    }
    UIFont *font = [[OLKiteABTesting sharedInstance] lightThemeFont1WithSize:17];
    if (font){
        [self.navigationItem.rightBarButtonItem setTitleTextAttributes:@{NSFontAttributeName : font} forState:UIControlStateNormal];
    }
    
    self.presentedModally = self.parentViewController.isBeingPresented || self.navigationController.viewControllers.firstObject == self;
    if (self.presentedModally) {
        NSURL *cancelUrl = [NSURL URLWithString:[OLKiteABTesting sharedInstance].cancelButtonIconURL];
        if (cancelUrl && ![[OLImageDownloader sharedInstance] cachedDataExistForURL:cancelUrl]){
            [[OLImageDownloader sharedInstance] downloadImageAtURL:cancelUrl withCompletionHandler:^(UIImage *image, NSError *error){
                if (error) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageWithCGImage:image.CGImage scale:2.0 orientation:UIImageOrientationUp] style:UIBarButtonItemStyleDone target:self action:@selector(onButtonCancelClicked)];
                });
            }];
        }
        else{
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Cancel", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") style:UIBarButtonItemStylePlain target:self action:@selector(onButtonCancelClicked)];

        }
    }
    else{
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.rightBarButtonItem = nil;
    }
    
    self.title = NSLocalizedStringFromTableInBundle(@"Shipping", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");

    UITapGestureRecognizer *tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onBackgroundClicked)];
    tgr.cancelsTouchesInView = NO; // allow table cell selection to happen as normal
    [self.tableView addGestureRecognizer:tgr];
    
    self.tableView.allowsMultipleSelectionDuringEditing = NO;
    
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 0)];
    
    self.kiteLabel = [[UILabel alloc] init];
    self.kiteLabel.text = NSLocalizedStringFromTableInBundle(@"Powered by Kite.ly", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    self.kiteLabel.font = [UIFont systemFontOfSize:13];
    self.kiteLabel.textColor = [UIColor lightGrayColor];
    self.kiteLabel.textAlignment = NSTextAlignmentCenter;
    [self.tableView.tableFooterView addSubview:self.kiteLabel];
    self.kiteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.tableView.tableFooterView addConstraint:[NSLayoutConstraint constraintWithItem:self.kiteLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.tableView.tableFooterView attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
    
    [self.printOrder costWithCompletionHandler:nil]; // ignore outcome, internally printOrder caches the result and this will speed up things when we hit the PaymentScreen *if* the user doesn't change destination shipping country as the voids shipping price
    
    if (self.printOrder.shippingAddress && [self.printOrder.shippingAddress isValidAddress]){
        self.shippingAddress = self.printOrder.shippingAddress;
    }
    
    if ([self.tableView respondsToSelector:@selector(setCellLayoutMarginsFollowReadableWidth:)]){
        self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    }
    
    if (!self.navigationItem.rightBarButtonItem && !self.presentedViewController){
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Save", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") style:UIBarButtonItemStyleDone target:self action:@selector(onButtonSaveClicked)];
    }
}

- (void)trackViewed{
#ifndef OL_NO_ANALYTICS
        [OLAnalytics trackDeliveryDetailsScreenViewedForOrder:self.printOrder variant:@"Classic" showPhoneEntryField:YES];
#endif
}

- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    
#ifndef OL_NO_ANALYTICS
    if (!self.navigationController){
        [OLAnalytics trackShippingScreenHitBackForOrder:self.printOrder];
    }
#endif
}

- (void)positionKiteLabel {
    [self.kiteLabel.superview removeConstraint:self.kiteLabelYCon];
    
    CGSize size = self.view.frame.size;
    CGFloat navBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height + self.navigationController.navigationBar.frame.size.height;
    CGFloat blankSpace = MAX(size.height - self.tableView.contentSize.height - navBarHeight - 5, 30);
    
    self.kiteLabelYCon = [NSLayoutConstraint constraintWithItem:self.kiteLabel attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.kiteLabel.superview attribute:NSLayoutAttributeBottom multiplier:1 constant:blankSpace];
    [self.kiteLabel.superview addConstraint:self.kiteLabelYCon];
}

- (void)onButtonCancelClicked {
#ifndef OL_NO_ANALYTICS
    [OLAnalytics trackShippingScreenHitBackForOrder:self.printOrder];
#endif
    if ([self.delegate respondsToSelector:@selector(checkoutViewControllerDidCancel:)]) {
        [self.delegate checkoutViewControllerDidCancel:self];
    } else {
        [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)onBackgroundClicked {
    [self.textFieldEmail resignFirstResponder];
    [self.textFieldPhone resignFirstResponder];
}

- (void)onButtonDoneClicked{
    if (![self hasUserProvidedValidDetailsToProgressToPayment]) {
        return;
    }
#ifndef OL_NO_ANALYTICS
    [OLAnalytics trackShippingScreenHitBackForOrder:self.printOrder];
#endif
    [self checkAndSaveAddress];
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)checkAndSaveAddress{
    [self.textFieldEmail resignFirstResponder];
    [self.textFieldPhone resignFirstResponder];
    
    NSString *email = [self userEmail];
    NSString *phone = [self userPhone];
    
    self.printOrder.email = email;
    self.printOrder.phone = phone;
    self.printOrder.shippingAddress = self.shippingAddress;
    
    if (![OLUserSession currentSession].kiteVc.discardDeliveryAddresses){
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:email forKey:kKeyEmailAddress];
        [defaults setObject:phone forKey:kKeyPhone];
        [defaults synchronize];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kOLNotificationUserSuppliedShippingDetails object:self userInfo:@{kOLKeyUserInfoPrintOrder: self.printOrder}];
}

- (void)onButtonNextClicked {
    if (![self hasUserProvidedValidDetailsToProgressToPayment]) {
        return;
    }
    [self checkAndSaveAddress];
    
    OLPaymentViewController *vc = [[OLPaymentViewController alloc] initWithPrintOrder:self.printOrder];
    vc.presentedModally = self.presentedModally;
    vc.delegate = self.delegate;
    
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)onButtonSaveClicked{
    if (![self hasUserProvidedValidDetailsToProgressToPayment]) {
        return;
    }
    [self checkAndSaveAddress];
#ifndef OL_NO_ANALYTICS
    [OLAnalytics trackShippingScreenHitBackForOrder:self.printOrder];
#endif
    [self.navigationController popViewControllerAnimated:YES];
}

- (void) viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    if (self.kiteLabel){
        [self positionKiteLabel];
    }
}

+ (BOOL)validateEmail:(NSString *)candidate {
    NSString *emailRegex = @"(?:[a-zA-Z0-9!#$%\\&'*+/=?\\^_`{|}~-]+(?:\\.[a-zA-Z0-9!#$%\\&'*+/=?\\^_`{|}"
    @"~-]+)*|\"(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21\\x23-\\x5b\\x5d-\\"
    @"x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])*\")@(?:(?:[a-zA-Z0-9](?:[a-"
    @"z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?|\\[(?:(?:25[0-5"
    @"]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-"
    @"9][0-9]?|[a-zA-Z0-9-]*[a-zA-Z0-9]:(?:[\\x01-\\x08\\x0b\\x0c\\x0e-\\x1f\\x21"
    @"-\\x5a\\x53-\\x7f]|\\\\[\\x01-\\x09\\x0b\\x0c\\x0e-\\x7f])+)\\])";
    NSPredicate *emailTest = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", emailRegex];
    return [emailTest evaluateWithObject:candidate];
}

- (BOOL)hasUserProvidedValidDetailsToProgressToPayment {
    /*
     * Only progress to Payment screen if the user has supplied a valid Delivery Address, Email & Telephone number.
     * Otherwise highlight the error to the user.
     */
    if (!self.shippingAddress) {
        [self scrollSectionToVisible:kSectionDeliveryDetails];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Missing Delivery Address", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") message:NSLocalizedStringFromTableInBundle(@"Please choose an address to have your order shipped to", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"Acknowledgent to an alert dialog.""") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){}]];
        [self presentViewController:ac animated:YES completion:NULL];
        return NO;
    }
    
    if (![OLCheckoutViewController validateEmail:[self userEmail]]) {
        [self scrollSectionToVisible:kSectionEmailAddress];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Invalid Email Address", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") message:NSLocalizedStringFromTableInBundle(@"Please enter a valid email address", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"Acknowledgent to an alert dialog.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){}]];
        [self presentViewController:ac animated:YES completion:NULL];
        return NO;
    }
    
    if ([self userPhone].length < kMinPhoneNumberLength) {
        [self scrollSectionToVisible:kSectionPhoneNumber];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:NSLocalizedStringFromTableInBundle(@"Invalid Phone Number", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") message:NSLocalizedStringFromTableInBundle(@"Please enter a valid phone number", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"") preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedStringFromTableInBundle(@"OK", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"Acknowledgent to an alert dialog.") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){}]];
        [self presentViewController:ac animated:YES completion:NULL];
        return NO;
    }
    
    return YES;
}

- (void)populateDefaultEmailAndPhone {
    if ([OLUserSession currentSession].kiteVc.discardDeliveryAddresses){
        self.textFieldEmail.text = self.printOrder.email;
        self.textFieldPhone.text = self.printOrder.phone;
        return;
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *email = self.printOrder.email ? self.printOrder.email : [defaults stringForKey:kKeyEmailAddress];
    if (!email){
        email = _userEmail;
    }
    NSString *phone = self.printOrder.phone ? self.printOrder.phone : [defaults stringForKey:kKeyPhone];
    if (!phone){
        phone = _userPhone;
    }
    if (self.textFieldEmail.text.length == 0) {
        if (email.length > 0) {
            self.textFieldEmail.text = email;
        } else if (self.userEmail.length > 0) {
            self.textFieldEmail.text = self.userEmail;
        }
    }
    
    if (self.textFieldPhone.text.length == 0) {
        if (phone.length > 0) {
            self.textFieldPhone.text = phone;
        } else if (self.userPhone.length > 0) {
            self.textFieldPhone.text = self.userPhone;
        }
    }
}


- (NSString *)userEmail {
    if (self.textFieldEmail == nil) {
        if ([OLUserSession currentSession].kiteVc.discardDeliveryAddresses){
            return @"";
        }
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *email = [defaults stringForKey:kKeyEmailAddress];
        return email ? email : @"";
    }
    
    return self.textFieldEmail.text;
}

- (NSString *)userPhone {
    if (self.textFieldPhone == nil) {
        if ([OLUserSession currentSession].kiteVc.discardDeliveryAddresses){
            return @"";
        }
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *phone = [defaults stringForKey:kKeyPhone];
        return phone ? phone : @"";
    }
    
    return self.textFieldPhone.text;
}

- (void)scrollSectionToVisible:(NSUInteger)section {
    CGRect sectionRect = [self.tableView rectForSection:section];
    [self.tableView scrollRectToVisible:sectionRect animated:YES];
}


#pragma mark - UITableViewDataSource methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == kSectionDeliveryDetails) {
        return NSLocalizedStringFromTableInBundle(@"Delivery Details", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    }
    else if (section == kSectionEmailAddress){
        return NSLocalizedStringFromTableInBundle(@"Email", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    }
    else if (section == kSectionPhoneNumber){
        return NSLocalizedStringFromTableInBundle(@"Phone", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    }
    else {
        return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == kSectionEmailAddress) {
        return NSLocalizedStringFromTableInBundle(@"We'll send you confirmation and order updates.", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    } else if (section == kSectionPhoneNumber) {
        return NSLocalizedStringFromTableInBundle(@"Required by the postal service in case there are any issues during delivery.", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    }
    
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == kSectionDeliveryDetails) {
        return self.shippingAddress ? 2 : 1;
    } else if (section == kSectionEmailAddress) {
        return 1;
    } else if (section == kSectionPhoneNumber) {
        return 1;
    }
    
    return 0;
}

- (void)onButtonCheckboxClicked:(UIButton *)sender{
    self.printOrder.optOutOfEmail = !self.printOrder.optOutOfEmail;
    
    [sender setImage:self.printOrder.optOutOfEmail ? [UIImage imageNamedInKiteBundle:@"checkbox_off"] : [UIImage imageNamedInKiteBundle:@"checkbox_on"] forState:UIControlStateNormal];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section{
    if (section == kSectionDeliveryDetails){
        return 0;
    }
    return 44;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section{
    if (section != kSectionEmailAddress){
        return nil;
    }
    if (![OLUserSession currentSession].kiteVc.showOptOutOfEmailsCheckbox){
        return nil;
    }
    
    UIView *cell = [[UIView alloc] init];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 11, 61, 21)];
    
    titleLabel.text = NSLocalizedStringFromTableInBundle(@"We'll send you confirmation and order updates. Uncheck this box to opt out of email campaigns.", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
    titleLabel.adjustsFontSizeToFitWidth = YES;
    titleLabel.tag = kTagInputFieldLabel;
    titleLabel.numberOfLines = 3;
    titleLabel.font = [UIFont systemFontOfSize:13];
    titleLabel.textColor = [UIColor darkGrayColor];
    
    [cell addSubview:titleLabel];
    
    UIButton *checkbox = [[UIButton alloc] init];
    [checkbox setImage:self.printOrder.optOutOfEmail ? [UIImage imageNamedInKiteBundle:@"checkbox_off"] : [UIImage imageNamedInKiteBundle:@"checkbox_on"] forState:UIControlStateNormal];
    [checkbox addTarget:self action:@selector(onButtonCheckboxClicked:) forControlEvents:UIControlEventTouchUpInside];
    checkbox.translatesAutoresizingMaskIntoConstraints = NO;
    [titleLabel.superview addSubview:checkbox];
    
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = NSDictionaryOfVariableBindings(titleLabel, checkbox);
    NSMutableArray *con = [[NSMutableArray alloc] init];
    
    NSArray *visuals = @[[NSString stringWithFormat:@"H:|-20-[titleLabel]-5-[checkbox(%f)]-20-|", checkbox.imageView.image.size.width],
                         @"V:[titleLabel(43)]",
                         @"V:[checkbox(43)]"];
    
    
    for (NSString *visual in visuals) {
        [con addObjectsFromArray: [NSLayoutConstraint constraintsWithVisualFormat:visual options:0 metrics:nil views:views]];
    }
    
    NSLayoutConstraint *textFieldCenterY = [NSLayoutConstraint constraintWithItem:titleLabel attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:titleLabel.superview attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
    NSLayoutConstraint *checkboxCenterY = [NSLayoutConstraint constraintWithItem:checkbox attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:checkbox.superview attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
    [con addObjectsFromArray:@[textFieldCenterY, checkboxCenterY]];
    
    [titleLabel.superview addConstraints:con];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    if (indexPath.section == kSectionDeliveryDetails) {
        static NSString *const kDeliveryAddressCell = @"DeliveryAddressCell";
        static NSString *const kAddDeliveryAddressCell = @"AddDeliveryAddressCell";
        
        if (self.shippingAddress && indexPath.row == 0) {
            cell = [tableView dequeueReusableCellWithIdentifier:kDeliveryAddressCell];
            if (cell == nil) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kDeliveryAddressCell];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            cell.textLabel.textColor = [UIColor blackColor];
            cell.imageView.image =  [UIImage imageNamedInKiteBundle:@"checkmark_on"];
            cell.textLabel.text = [self.shippingAddress fullNameFromFirstAndLast];
            cell.detailTextLabel.text = [self.shippingAddress descriptionWithoutRecipient];
        } else {
            cell = [tableView dequeueReusableCellWithIdentifier:kAddDeliveryAddressCell];
            if (cell == nil) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kAddDeliveryAddressCell];
                cell.textLabel.adjustsFontSizeToFitWidth = YES;
                cell.textLabel.textColor = kColourLightBlue;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Choose Delivery Address", @"KitePrintSDK", [OLKiteUtils kiteLocalizationBundle], @"");
        }
    } else if (indexPath.section == kSectionEmailAddress) {
        static NSString *const TextFieldCell = @"EmailFieldCell";
        cell = [tableView dequeueReusableCellWithIdentifier:TextFieldCell];
        if (cell == nil) {
            cell = [self createTextFieldCellWithReuseIdentifier:TextFieldCell keyboardType:UIKeyboardTypeEmailAddress];
            self.textFieldEmail = (UITextField *) [cell viewWithTag:kInputFieldTag];
            self.textFieldEmail.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.textFieldEmail.autocorrectionType = UITextAutocorrectionTypeNo;
            [self populateDefaultEmailAndPhone];
        }
        
    } else if (indexPath.section == kSectionPhoneNumber) {
        static NSString *const TextFieldCell = @"PhoneFieldCell";
        cell = [tableView dequeueReusableCellWithIdentifier:TextFieldCell];
        if (cell == nil) {
            cell = [self createTextFieldCellWithReuseIdentifier:TextFieldCell keyboardType:UIKeyboardTypePhonePad];
            self.textFieldPhone = (UITextField *) [cell viewWithTag:kInputFieldTag];
            [self populateDefaultEmailAndPhone];
        }
    }
    
    return cell;
}

- (UITableViewCell *)createTextFieldCellWithReuseIdentifier:(NSString *)identifier keyboardType:(UIKeyboardType)type {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithFrame:CGRectMake(20, 0, [UIScreen mainScreen].bounds.size.width, 43)];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UITextField *inputField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 43)];
    inputField.delegate = self;
    inputField.tag = kInputFieldTag;
    [inputField setKeyboardType:type];
    [inputField setReturnKeyType:UIReturnKeyNext];
    [cell addSubview:inputField];
    
    UIView *view = inputField;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = NSDictionaryOfVariableBindings(view);
    NSMutableArray *con = [[NSMutableArray alloc] init];
    
    NSArray *visuals = @[@"H:|-20-[view]-0-|", @"V:[view(43)]"];
    
    
    for (NSString *visual in visuals) {
        [con addObjectsFromArray: [NSLayoutConstraint constraintsWithVisualFormat:visual options:0 metrics:nil views:views]];
    }
    
    NSLayoutConstraint *centerY = [NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:view.superview attribute:NSLayoutAttributeCenterY multiplier:1 constant:0];
    [con addObject:centerY];
    
    [view.superview addConstraints:con];
    
    
    return cell;
}


#pragma mark - UITableViewDelegate methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == kSectionDeliveryDetails) {
        if ([OLAddress addressBook].count > 0) {
            OLAddressPickerController *addressPicker = [[OLAddressPickerController alloc] init];
            addressPicker.delegate = self;
            addressPicker.allowsMultipleSelection = NO;
            if (self.shippingAddress){
                addressPicker.selected = [@[self.shippingAddress] mutableCopy];
            }
            addressPicker.modalPresentationStyle = [OLUserSession currentSession].kiteVc.modalPresentationStyle;
            [self presentViewController:addressPicker animated:YES completion:nil];
        } else {
            OLAddressEditViewController *editVc = [[OLAddressEditViewController alloc] init];
            editVc.delegate = self;
            UINavigationController *nvc = [[OLNavigationController alloc] initWithRootViewController:editVc];
            nvc.modalPresentationStyle = [OLUserSession currentSession].kiteVc.modalPresentationStyle;
            [self presentViewController:nvc animated:YES completion:nil];
        }
    }
}

#pragma mark - UITextFieldDelegate methods

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.textFieldEmail) {
        [self.textFieldPhone becomeFirstResponder];
    }
    else{
        [textField resignFirstResponder];
    }
    
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    self.activeTextView = textField;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string{
    [[OLUserSession currentSession].kiteVc setLastTouchDate:[NSDate date] forViewController:self];
    return YES;
}

#pragma mark - OLAddressPickerController delegate

- (void)addressPicker:(OLAddressPickerController *)picker didFinishPickingAddresses:(NSArray<OLAddress *> *)addresses {
    OLAddress *addressCopy = [addresses.firstObject copy];
    self.shippingAddress = addressCopy;

    [self dismissViewControllerAnimated:YES completion:nil];
    [self.tableView reloadSections:[[NSIndexSet alloc] initWithIndex:kSectionDeliveryDetails] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)addressPickerDidCancelPicking:(OLAddressPickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
