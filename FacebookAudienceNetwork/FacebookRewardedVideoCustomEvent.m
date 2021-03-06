//
//  FacebookRewardedVideoCustomEvent.m
//
//  Created by Mopub on 4/12/17.
//
#import <FBAudienceNetwork/FBAudienceNetwork.h>
#import "FacebookRewardedVideoCustomEvent.h"
#import "FacebookAdapterConfiguration.h"

#if __has_include("MoPub.h")
    #import "MPLogging.h"
    #import "MoPub.h"
    #import "MPReward.h"
    #import "MPRealTimeTimer.h"
#endif

//Timer to record the expiration interval
#define FB_ADS_EXPIRATION_INTERVAL  3600

@interface FacebookRewardedVideoCustomEvent () <FBRewardedVideoAdDelegate>

@property (nonatomic, strong) FBRewardedVideoAd *fbRewardedVideoAd;
@property (nonatomic, strong) MPRealTimeTimer *expirationTimer;
@property (nonatomic, assign) BOOL hasTrackedImpression;
@property (nonatomic, copy) NSString *fbPlacementId;

@end

@implementation FacebookRewardedVideoCustomEvent

- (void)initializeSdkWithParameters:(NSDictionary *)parameters {
    // No SDK initialization method provided.
}

#pragma mark - MPFullscreenAdAdapter Override

- (BOOL)isRewardExpected
{
    return YES;
}

- (BOOL)enableAutomaticImpressionAndClickTracking
{
    return NO;
}

- (BOOL)hasAdAvailable
{
    //Verify that the rewarded video is precached
    return (self.fbRewardedVideoAd != nil && self.fbRewardedVideoAd.isAdValid);
}

- (void)requestAdWithAdapterInfo:(NSDictionary *)info adMarkup:(NSString *)adMarkup
{
    if (![info objectForKey:@"placement_id"]) {
        NSError *error = [self createErrorWith:@"Invalid Facebook placement ID"
                                     andReason:@""
                                 andSuggestion:@""];
        
        MPLogAdEvent([MPLogEvent adLoadFailedForAdapter:NSStringFromClass(self.class) error:error], nil);
        
        [self.delegate fullscreenAdAdapter:self didFailToLoadAdWithError:error];
        return;
    }
    
    self.fbRewardedVideoAd = [[FBRewardedVideoAd alloc] initWithPlacementID:[info objectForKey:@"placement_id"]];
    self.fbRewardedVideoAd.delegate = self;
    
    [FBAdSettings setMediationService:[FacebookAdapterConfiguration mediationString]];

    // Load the advanced bid payload.
    if (adMarkup != nil) {
        MPLogInfo(@"Loading Facebook rewarded video ad markup for Advanced Bidding");
        [self.fbRewardedVideoAd loadAdWithBidPayload:adMarkup];

        MPLogAdEvent([MPLogEvent adLoadAttemptForAdapter:NSStringFromClass(self.class) dspCreativeId:nil dspName:nil], self.fbPlacementId);
    }
    // Request a rewarded video ad.
    else {
        MPLogInfo(@"Loading Facebook rewarded video ad");
        [self.fbRewardedVideoAd loadAd];

        MPLogAdEvent([MPLogEvent adLoadAttemptForAdapter:NSStringFromClass(self.class) dspCreativeId:nil dspName:nil], self.fbPlacementId);
    }
}

- (void)presentAdFromViewController:(UIViewController *)viewController
{
    if(![self hasAdAvailable])
    {
        NSError *error = [self createErrorWith:@"Error in loading Facebook Rewarded Video"
                                     andReason:@""
                                 andSuggestion:@""];

        MPLogAdEvent([MPLogEvent adShowFailedForAdapter:NSStringFromClass(self.class) error:error], self.fbPlacementId);
        [self.delegate fullscreenAdAdapter:self didFailToShowAdWithError:error];
    }
    else
    {
        MPLogAdEvent([MPLogEvent adShowAttemptForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);

        MPLogAdEvent([MPLogEvent adWillAppearForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
        [self.delegate fullscreenAdAdapterAdWillAppear:self];

        [self.fbRewardedVideoAd showAdFromRootViewController:viewController];

        MPLogAdEvent([MPLogEvent adDidAppearForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
        [self.delegate fullscreenAdAdapterAdDidAppear:self];
    }
}

-(void)dealloc{
    [self cancelExpirationTimer];
    self.fbRewardedVideoAd.delegate = nil;
}

-(void)cancelExpirationTimer
{
    if (self.expirationTimer != nil)
    {
        [self.expirationTimer invalidate];
        self.expirationTimer = nil;
    }
}

#pragma mark FBRewardedVideoAdDelegate methods

/*!
 @method
 
 @abstract
 Sent after an ad has been clicked by the person.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 */
- (void)rewardedVideoAdDidClick:(FBRewardedVideoAd *)rewardedVideoAd
{
    MPLogAdEvent([MPLogEvent adTappedForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
    [self.delegate fullscreenAdAdapterDidReceiveTap:self];
    [self.delegate fullscreenAdAdapterDidTrackClick:self];
    [self.delegate fullscreenAdAdapterWillLeaveApplication:self];
}

/*!
 @method
 
 @abstract
 Sent when an ad has been successfully loaded.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 */
- (void)rewardedVideoAdDidLoad:(FBRewardedVideoAd *)rewardedVideoAd
{
    
    [self cancelExpirationTimer];

    [self.delegate fullscreenAdAdapterDidLoadAd:self];
    MPLogAdEvent([MPLogEvent adLoadSuccessForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
    
    // introduce timer for 1 hour per expiration logic introduced by FB
    __weak __typeof__(self) weakSelf = self;
    self.expirationTimer = [[MPRealTimeTimer alloc] initWithInterval:FB_ADS_EXPIRATION_INTERVAL block:^(MPRealTimeTimer *timer){
        __strong __typeof__(weakSelf) strongSelf = weakSelf;
        if (strongSelf && !strongSelf.hasTrackedImpression) {
            [strongSelf.delegate fullscreenAdAdapterDidExpire:strongSelf];
            
            NSError *error = [self createErrorWith:@"Facebook rewarded video ad expired  per Audience Network's expiration policy"
                                         andReason:@""
                                     andSuggestion:@""];
            
            MPLogAdEvent([MPLogEvent adShowFailedForAdapter:NSStringFromClass(self.class) error:error], self.fbPlacementId);

            strongSelf.fbRewardedVideoAd = nil;
        }
    }];
    [self.expirationTimer scheduleNow];
}

- (NSError *)createErrorWith:(NSString *)description andReason:(NSString *)reaason andSuggestion:(NSString *)suggestion {
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey: NSLocalizedString(description, nil),
                               NSLocalizedFailureReasonErrorKey: NSLocalizedString(reaason, nil),
                               NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(suggestion, nil)
                               };

    return [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:userInfo];
}

/*!
 @method
 
 @abstract
 Sent after an FBRewardedVideoAd object has been dismissed from the screen, returning control
 to your application.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 */
- (void)rewardedVideoAdDidClose:(FBRewardedVideoAd *)rewardedVideoAd
{
    MPLogAdEvent([MPLogEvent adDidDisappearForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
    [self.delegate fullscreenAdAdapterAdDidDisappear:self];
}

/*!
 @method
 
 @abstract
 Sent immediately before an FBRewardedVideoAd object will be dismissed from the screen.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 */
- (void)rewardedVideoAdWillClose:(FBRewardedVideoAd *)rewardedVideoAd
{
    MPLogAdEvent([MPLogEvent adWillDisappearForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
    [self.delegate fullscreenAdAdapterAdWillDisappear:self];
}

/*!
 @method
 
 @abstract
 Sent after an FBRewardedVideoAd fails to load the ad.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 @param error An error object containing details of the error.
 */
- (void)rewardedVideoAd:(FBRewardedVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
    [self cancelExpirationTimer];

    MPLogAdEvent([MPLogEvent adLoadFailedForAdapter:NSStringFromClass(self.class) error:error], nil);
    [self.delegate fullscreenAdAdapter:self didFailToLoadAdWithError:error];
}

/*!
 @method
 
 @abstract
 Sent after the FBRewardedVideoAd object has finished playing the video successfully.
 Reward the user on this callback.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 */
- (void)rewardedVideoAdVideoComplete:(FBRewardedVideoAd *)rewardedVideoAd
{
    MPLogInfo(@"Facebook rewarded video ad has finished playing successfully");
    // Passing the reward type and amount as unspecified. Set the reward value in mopub UI.
    MPReward *reward = [[MPReward alloc] initWithCurrencyAmount:@(kMPRewardedVideoRewardCurrencyAmountUnspecified)];
    [self.delegate fullscreenAdAdapter:self willRewardUser:reward];
}

/*!
 @method
 
 @abstract
 Sent immediately before the impression of an FBRewardedVideoAd object will be logged.
 
 @param rewardedVideoAd An FBRewardedVideoAd object sending the message.
 */
- (void)rewardedVideoAdWillLogImpression:(FBRewardedVideoAd *)rewardedVideoAd
{
    [self.delegate fullscreenAdAdapterDidTrackImpression:self];
    [self cancelExpirationTimer];

    MPLogAdEvent([MPLogEvent adShowSuccessForAdapter:NSStringFromClass(self.class)], self.fbPlacementId);
    //set the tracker to true when the ad is shown on the screen. So that the timer is invalidated.
    self.hasTrackedImpression = true;
}

@end
