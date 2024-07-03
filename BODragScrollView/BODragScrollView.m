//
//  BODragScrollView.m
//  BODragScrollView
//
//  Created by bo on 2019/6/27.
//  Copyright © 2019 bo. All rights reserved.
//

#import "BODragScrollView.h"
#import <objc/runtime.h>

NSInteger bo_findIdxInFloatArrayByValue(NSArray<NSNumber *> *ar,
                                        CGFloat value,
                                        BOOL nearby,
                                        BOOL ceil) {
    //ar需要有序（升序），不重复
    for (NSInteger i = 0; i < ar.count; i++) {
        CGFloat thef = ar[i].floatValue;
        if (value > thef) {
            if (i + 1 < ar.count) {
                continue;
            } else {
                return i;
            }
        } else if (value < thef) {
            if (i - 1 >= 0) {
                if (nearby) {
                    CGFloat pf = ar[i - 1].floatValue;
                    CGFloat df = fabs(value - pf) - fabs(thef - value);
                    if (df > 0) {
                        return i;
                    } else if (df < 0) {
                        return (i - 1);
                    } else {
                        return (ceil ? i : (i - 1));
                    }
                } else {
                    return (ceil ? i : (i - 1));
                }
            } else {
                return i;
            }
        } else {
            return i;
        }
    }
    return 0;
}

static UIEdgeInsets sf_common_contentInset(UIScrollView * __nonnull scrollView) {
    if (@available(iOS 11.0, *)) {
        return scrollView.adjustedContentInset;
    } else {
        return scrollView.contentInset;
    }
}

#define sf_uifloat_equal(a, b) (fabs(a - b) <= 0.01)

#define sf_indictor_tag (9919)

typedef struct BODragScrollAttachInfo {
    NSInteger scrollViewIdx; //对应的scrollView索引值(一次可以捕获多个scrollView)，0表示没有，-1表示currScrollView
    
    CGFloat displayH; //吸附点的对应展示高度
    CGFloat dragSVOffsetY; //吸附点的对应offset.y
    
    BOOL dragInner; //吸附点是否可以滑动内部scrollView
    CGFloat innerOffsetA; //若吸附点可以滑动内部scrollView，对应的滑动区域的起点
    CGFloat innerOffsetB; //对应的滑动区域的终点
    
    //非核心属性，辅助计算用，值 = dragSVOffsetY + (innerOffsetB - innerOffsetA)
    CGFloat dragSVOffsetY2;
} BODragScrollAttachInfo;

static CGFloat sf_getOnePxiel(void) {
    static CGFloat onepxiel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        onepxiel = 1.f / [UIScreen mainScreen].scale;
    });
    return onepxiel;
}

static void bo_swizzleMethod(Class cls, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSelector);
    BOOL didAddMethod =\
    class_addMethod(cls, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(cls, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

//临时方案，解决被捕获scrollView的isDrag、track等状态获取
@interface BODragScrollWeekPtItem : NSObject

@property (nonatomic, weak) BODragScrollView *dragScrollView;

@end

@implementation BODragScrollWeekPtItem
@end

@interface UIScrollView (bo_dragScroll)

@property (nonatomic, weak) BODragScrollView *bo_dragScrollView;

@property (nonatomic, readonly) BOOL bods_isDragging;
@property (nonatomic, readonly) BOOL bods_isTracking;
@property (nonatomic, readonly) BOOL bods_isDecelerating;

@property (nonatomic, readwrite) CGPoint bo_contentOffset;
@property (nonatomic, readwrite) CGSize bo_contentSize;
@property (nonatomic, readwrite) UIEdgeInsets bo_contentInset;

@end

@implementation UIScrollView (bo_dragScroll)

- (CGPoint)bo_contentOffset {
    return self.contentOffset;
}

- (void)setBo_contentOffset:(CGPoint)bo_contentOffset {
    if (!CGPointEqualToPoint(self.contentOffset, bo_contentOffset)) {
        self.contentOffset = bo_contentOffset;
    }
}

- (CGSize)bo_contentSize {
    return self.contentSize;
}

- (void)setBo_contentSize:(CGSize)bo_contentSize {
    if (!CGSizeEqualToSize(self.contentSize, bo_contentSize)) {
        self.contentSize = bo_contentSize;
    }
}

- (UIEdgeInsets)bo_contentInset {
    return self.contentInset;
}

- (void)setBo_contentInset:(UIEdgeInsets)bo_contentInset {
    if (!UIEdgeInsetsEqualToEdgeInsets(self.contentInset, bo_contentInset)) {
        self.contentInset = bo_contentInset;
    }
}

+ (void)load {
    bo_swizzleMethod(self, @selector(isDragging), @selector(bods_isDragging));
    bo_swizzleMethod(self, @selector(isTracking), @selector(bods_isTracking));
    bo_swizzleMethod(self, @selector(isDecelerating), @selector(bods_isDecelerating));
}

- (void)setBo_dragScrollView:(BODragScrollView *)bo_dragScrollView {
    BODragScrollWeekPtItem *item;
    if (bo_dragScrollView) {
        item = [BODragScrollWeekPtItem new];
        item.dragScrollView = bo_dragScrollView;
    }
    objc_setAssociatedObject(self, @selector(bo_dragScrollView), item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BODragScrollView *)bo_dragScrollView {
    BODragScrollWeekPtItem *item = objc_getAssociatedObject(self, @selector(bo_dragScrollView));
    if ([item isKindOfClass:[BODragScrollWeekPtItem class]]) {
        return item.dragScrollView;
    }
    return nil;
}

- (BOOL)bods_isDragging {
    UIScrollView *sv = self.bo_dragScrollView;
    if (sv) {
        return [sv bods_isDragging];
    } else {
        return [self bods_isDragging];
    }
}

- (BOOL)bods_isTracking {
    UIScrollView *sv = self.bo_dragScrollView;
    if (sv) {
        return [sv bods_isTracking];
    } else {
        return [self bods_isTracking];
    }
}

- (BOOL)bods_isDecelerating {
    UIScrollView *sv = self.bo_dragScrollView;
    if (sv) {
        return [sv bods_isDecelerating];
    } else {
        return [self bods_isDecelerating];
    }
}

@end

//自定义手势检测，用来弥补一些系统行为漏掉的动作
@interface BODragScrollTapGes : UIGestureRecognizer <UIGestureRecognizerDelegate>

- (void)finishRecognizer;

@end

@implementation BODragScrollTapGes {
    CGPoint _uPt;
    NSMutableArray<UITouch *> *_curTouches;
    BOOL _hasMulti;
}

- (instancetype)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        self.cancelsTouchesInView = NO;
        self.delaysTouchesEnded = NO;
        self.delegate = self;
    }
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)reset {
    [super reset];
    _uPt = CGPointZero;
    _curTouches = [NSMutableArray new];
    _hasMulti = NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    BOOL isnewbegan = (0 == _curTouches.count);
    [touches enumerateObjectsUsingBlock:^(UITouch * _Nonnull obj, BOOL * _Nonnull stop) {
        [_curTouches addObject:obj];
    }];
    
    if (isnewbegan && _curTouches.count > 0) {
        UITouch *thetouch = _curTouches.firstObject;
        _uPt = [thetouch locationInView:self.view];
        self.state = UIGestureRecognizerStateBegan;
    }
    
    if (_curTouches.count > 1) {
        _hasMulti = YES;
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self __touchesFinish:touches event:event];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self __touchesFinish:touches event:event];
}

- (void)__touchesFinish:(NSSet<UITouch *> *)touches event:(UIEvent *)event {
    if (_hasMulti) {
        //有过多重touch，等所有touch都抬起后再end
        [touches enumerateObjectsUsingBlock:^(UITouch * _Nonnull obj, BOOL * _Nonnull stop) {
            [_curTouches removeObject:obj];
        }];
        
        if (0 == _curTouches.count) {
            self.state = UIGestureRecognizerStateEnded;
            _hasMulti = NO;
        }
    } else {
        self.state = UIGestureRecognizerStateEnded;
    }
}

- (void)finishRecognizer {
    if (UIGestureRecognizerStatePossible == self.state) {
        self.state = UIGestureRecognizerStateFailed;
    } else {
        self.state = UIGestureRecognizerStateCancelled;
    }
}

@end

@interface BODragScrollView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

/*
 当前embedView展示的高度
 */
@property (nonatomic, assign) CGFloat currDisplayH;

@property (nonatomic) BODragScrollAttachInfo *innerSVAttInfAr;
@property (nonatomic, assign) NSInteger innerSVAttInfCount;

@property (nonatomic, assign) BOOL innerSetting;

@property (nonatomic, strong) UIScrollView *currentScrollView; //当前捕获的内部scrollView
@property (nonatomic, assign) BOOL currentScrollViewHasObserver;


@property (nonatomic, assign) BOOL isScrollAnimating;

@property (nonatomic, strong) NSNumber *needsAnimatedToH;

@end

@implementation BODragScrollView {
    CGRect _lastLayoutBounds;   //记录上次布局的bounds
    BOOL _hasLayoutEmbedView;   //embedView设置后，有没有完成过布局。
    
    NSNumber *_needsDisplayH;   //一些设置displayH的时机View还没有布局，先存下在，布局的时候读取并设置。
    
    BOOL _waitDidTargetTo; //调用了willTargetTo，等待调用DidTargetTo
    BOOL _ignoreWaitDidTargetTo; //在内部设置时忽视_waitDidTargetTo
    BOOL _waitMayAnimationScroll;
    void (^_animationScrollDidEndBlock)(void);
    
    //辅助运算
    CGFloat _minScrollInnerOSy; //捕获内部sc的可滑动最小Offsety
    CGFloat _maxScrollInnerOSy; //捕获内部sc的可滑动最大Offsety
    CGFloat _totalScrollInnerOSy; //最后一次获取的内部sc允许滑动的距离
    CGSize _lastInnerSCSize; //最后一次获取的内部sc contentSize
    CGPoint _lastSetInnerOSy; //由内部控制的最后一次设置的捕获sc的osy
    CGFloat _lastAniScrollEndTS; //scrollTo自然滑动动画结束的时间
    BOOL _needsFixDisplayHWhenTouchEnd;
    //innerscroll已经滑动过了，当前对应的attach点可能在下部-1   可能在上部1。没有时为0
    NSInteger _missAttachAndNeedsReload;
    BOOL _forceResetWhenScroll;
    NSMutableDictionary *_innerSVBehaviorInfo;
    
    __weak UIControl *_theCtrWhenDecInner; //decelerating时点击了某UIControl，为了不使scrollView的系统机制无效其点击事件，手动传递action
    BOOL _lastScrollIsInner; //最后一次滑动位置变化（包括内外），是否是捕获的内部sv
    NSValue *_scrollBeganLoc; //滑动开始的点
    NSNumber *_dragBeganDH; //滑动开始的展示高度
    BOOL _dragDHHasChange; //从拖拽起始，到终止，展示高度是否发生过变化（即使起终点相同，中间变化过也算）
    BODragScrollTapGes *_dsTapGes;
    
    //触发内部scrollView时会切换到内部scrollView的rate，用该处存储自己的的rate
    UIScrollViewDecelerationRate _curDecelerationRate;
    
    //绑定内部时，会把ScrollToTop设置为NO，如果原本是YES，需要在结束时恢复到YES
    BOOL _needsRecoverScrollVAllowScrollToTop;
    
    BOOL _didTouchWebView;
}

//在设置前后添加标识位，其它方法接收到滑动发生时，可根据标识位识别是否是此处设置导致。
- (void)innerSetting:(void (^)(void))innerSettingBlock {
#if DEBUG
    if (NO != self.innerSetting) {
        NSLog(@"~~~⚠️BODragScrollView：innerSetting:(void (^)(void))innerSettingBlock NO != self.innerSetting 需观察");
    }
#endif
    
    if (innerSettingBlock) {
        self.innerSetting = YES;
        innerSettingBlock();
        self.innerSetting = NO;
    }
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(iOS 11.0, *)) {
            self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
            self.panGestureRecognizer.name = @"BODragScrollView-PanGesture";
        }
        
        _innerSetting = NO;
        _lastLayoutBounds = CGRectZero;
        _hasLayoutEmbedView = NO;
        _prefBouncesCardTop = YES;
        _prefBouncesCardBottom = NO;
        _allowBouncesCardTop = YES;
        _allowBouncesCardBottom = YES;
        _autoShowInnerIndictor = YES;
        _defaultDecelerateStyle = BODragScrollDecelerateStyleNature;
        _caAnimationSpeed = 1000;
        _caAnimationBaseDur = 0.12;
        _caAnimationMaxDur = 0.32;
        _caAnimationUseSpring = YES;
        _waitDidTargetTo = NO;
        _ignoreWaitDidTargetTo = NO;
        _waitMayAnimationScroll = NO;
        _prefDragCardWhenExpand = NO;
        _autoResetInnerSVOffsetWhenAttachMiss = NO;
        _shouldSimultaneouslyWithOtherGesture = YES;
        _shouldFailureOtherTapGestureWhenDecelerating = YES;
        _curDecelerationRate = UIScrollViewDecelerationRateFast;
        super.decelerationRate = UIScrollViewDecelerationRateFast;
        super.delegate = self;
        super.showsHorizontalScrollIndicator = NO;
        super.showsVerticalScrollIndicator = NO;
        super.delaysContentTouches = NO;
        super.canCancelContentTouches = YES;
        super.scrollsToTop = NO;
        self.autoresizesSubviews = NO;
        if (@available(iOS 13.0, *)) {
            super.automaticallyAdjustsScrollIndicatorInsets = NO;
        }
        
        _dsTapGes = [[BODragScrollTapGes alloc] initWithTarget:self action:@selector(onTapGes:)];
        if (@available(iOS 11.0, *)) {
            _dsTapGes.name = @"BODragScrollView-tapGesture";
        }
        _dsTapGes.delegate = self;
        [self addGestureRecognizer:_dsTapGes];
    }
    return self;
}

#if DEBUG
- (void)setDelegate:(id<UIScrollViewDelegate>)delegate {
    if (nil == delegate || self == delegate) {
        [super setDelegate:delegate];
    } else {
        NSString *str = @"请勿修改 BODragScrollView : UIScrollVIew 的 delegate，使用.dragScrollDelegate";
        NSLog(@"\n\n⚠️ exception:%@\n%@", str, [NSThread callStackSymbols]);
        @throw [NSException exceptionWithName:@"非法使用"
                                       reason:str
                                     userInfo:nil];
    }
}
#endif

- (void)setDecelerationRate:(UIScrollViewDecelerationRate)decelerationRate {
    if (_innerSetting) {
        //内部设置，恢复rate
        [super setDecelerationRate:decelerationRate];
    } else {
        //外部设置，修改_curDecelerationRate值
        _curDecelerationRate = decelerationRate;
        if (!_currentScrollView) {
            //若当前没有_currentScrollView同步更新当前的rate
            //若有，在滑动过程中自会从_curDecelerationRate读取设置，不需要在此处更新
            [super setDecelerationRate:decelerationRate];
        }
    }
}

- (BOOL)touchesShouldCancelInContentView:(UIView *)view {
    return YES;
}

- (NSInteger)__priorityBehaviorForInnerSV:(UIScrollView *)sv {
    NSArray<NSDictionary *> *otherscar = _innerSVBehaviorInfo ? [_innerSVBehaviorInfo objectForKey:@"otherSVBehaviorAr"] : nil;
    if (otherscar
        && [otherscar isKindOfClass:[NSArray class]]
        && otherscar.count > 0) {
        
        __block NSInteger prioritybeg = NSNotFound;
        [otherscar enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            UIScrollView *objsv = [obj objectForKey:@"sv"];
            if (objsv == sv) {
                NSNumber *priorityobj = [obj objectForKey:@"priority"];
                if (nil != priorityobj) {
                    prioritybeg = priorityobj.integerValue;
                }
                *stop = YES;
            }
        }];
        
        return prioritybeg;
    } else {
        return NSNotFound;
    }
}

/*
 寻找从targetView到endView层级之间可以竖向滑动的scrollView
 endView: 终点，不传则默认_embedView
 includeTarget: 是否判定targetView
 judgeInnerSVBehaviorInfo: 是否判定InnerSVBehaviorInfo信息
 */
- (NSMutableArray<UIScrollView *> *)__seekScrollViewMultipleNesting:(UIView *)targetView
                                                            endView:(UIView *)endView
                                                      includeTarget:(BOOL)includeTarget
                                           judgeInnerSVBehaviorInfo:(BOOL)judgeInnerSVBehaviorInfo {
    if (!endView) {
        endView = _embedView;
    }
    if (!targetView
        || !endView) {
        return nil;
    }
    NSMutableArray *muar = @[].mutableCopy;
    UIResponder *resp = includeTarget ? targetView : targetView.nextResponder;
    while (resp) {
        if (endView == resp
            || nil == resp) {
            break;
        }
        
        if ([resp isKindOfClass:[UIScrollView class]] && [(UIScrollView *)resp isScrollEnabled]) {
            UIScrollView *scv = (UIScrollView *)resp;
            UIEdgeInsets inset = sf_common_contentInset(scv);
            BOOL canScrollVertical = ((scv.contentSize.height + inset.top + inset.bottom) > CGRectGetHeight(scv.bounds));
            if (canScrollVertical) {
                if (judgeInnerSVBehaviorInfo) {
                    NSString *svptr = [NSString stringWithFormat:@"%p", scv];
                    NSNumber *prioritynum = [_innerSVBehaviorInfo objectForKey:svptr];
                    if ([prioritynum isKindOfClass:[NSNumber class]]
                        && prioritynum.integerValue == 3) {
                        [muar addObject:scv];
                    }
                } else {
                    [muar addObject:scv];
                }
            }
        }
        
        resp = resp.nextResponder;
    }
    return muar;
}

/*
 通过索引值获取捕获的scrollView
 */
- (UIScrollView *)__obtainScrollViewWithIdx:(NSInteger)idx {
    if (-1 == idx) {
        return _currentScrollView;
    } else {
        return [_innerSVBehaviorInfo objectForKey:@(idx)];
    }
}

/*
 有监测到超过1个可捕获的scrollView时，才会往svBehaviorDic里塞内容，否则svBehaviorDic没意义就不塞内容
 */
- (UIScrollView *)__seekTargetScrollViewFrom:(UIView *)view svBehaviorDic:(NSMutableDictionary *)svBehaviorDic {
    
    NSMutableArray<NSMutableDictionary *> *svbehar;
    if (svBehaviorDic) {
        svbehar = @[].mutableCopy;
    }
    
    //优先级：可滑动的ScrollView > tag标记的 > 智能判断高度最高的，都没有传nil; force=YES，相同时也刷新being和end点
    UIScrollView *maxhsc = nil; //高度最大的scrollView
    UIScrollView *thsc = nil;   //寻找第一个可滑动的scrollView
    UIResponder *resp = view;
    //计算有几层scrollView嵌套，标记其层次
    NSInteger hierarchy = 0;
    
    UIView *thewebview = nil;
    
    while (resp) {
        if (self == resp) {
            break;
        }
        
        if ([resp isKindOfClass:[UIScrollView class]] && [(UIScrollView *)resp isScrollEnabled]) {
            UIScrollView *scv = (UIScrollView *)resp;
            hierarchy += 1;
            BOOL scvalid = YES;
            if (self.dragScrollDelegate &&
                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:canCatchInnerSV:)]) {
                scvalid = [self.dragScrollDelegate dragScrollView:self canCatchInnerSV:scv];
            }
            
            NSMutableDictionary *scdic;
            if (svbehar) {
                scdic = @{}.mutableCopy;
                [scdic setObject:scv forKey:@"sv"];
            }
            
            /*
             0：该ScrollView的交互和滑动效果将与DragScrollView共存
             -1: 该ScrollView的交互与DragScrollView不共存，若冲突则取消该ScrollView的交互响应
             1: 该ScrollView的交互与DragScrollView不共存，若冲突则取消该DragScrollView的交互响应
             2：该ScrollView的交互与DragScrollView不共存, 但冲突时不做强制处理，交给系统默认行为(内部的横滑scrollView默认使用该优先级，用来保障横滑和竖滑不共存，并视滑动方向自动选择哪个有效)
             3: 参与交互滑动
             */
            NSInteger priority = 0;
            if (scvalid) {
                priority = 3;
                UIEdgeInsets inset = sf_common_contentInset(scv);
                if (!thsc
                    && ((scv.contentSize.height + inset.top + inset.bottom) > CGRectGetHeight(scv.bounds))) {
                    thsc = scv;
                    if (!svbehar) {
                        break;
                    }
                } else {
                    if (scv.contentSize.width + inset.left + inset.right <= CGRectGetWidth(scv.bounds)) {
                        //非横向滑动scrollView默认找最高的
                        if (!maxhsc) {
                            maxhsc = scv;
                        } else {
                            if (CGRectGetHeight(scv.frame) > CGRectGetHeight(maxhsc.frame)) {
                                maxhsc = scv;
                            }
                        }
                    } else {
                        //横滑scv，不共存，不指定优先级，走系统默认行为
                        priority = 2;
                    }
                }
                
            } else {
                //不处理捕获
                priority = 2;
            }
            
            if (scdic) {
                [scdic setObject:@(priority) forKey:@"priority"];
                [svbehar addObject:scdic];
            }
            
            
        }
        
        if (nil == thewebview
            && [NSStringFromClass([resp class]) isEqualToString:@"WKWebView"]
            && [resp isKindOfClass:[UIView class]]) {
            thewebview = (id)resp;
        }
        
        resp = resp.nextResponder;
    }
    
    if (nil != thewebview
        && svBehaviorDic) {
        [svBehaviorDic setObject:thewebview forKey:@"webView"];
    }
    
    UIScrollView *selsc = (thsc ? : maxhsc);
    
    if (svBehaviorDic && svbehar.count > 1) {
        __block NSMutableDictionary *catchscdic;
        [svbehar enumerateObjectsUsingBlock:^(NSMutableDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            UIScrollView *objsc = [obj objectForKey:@"sv"];
            if (objsc == selsc) {
                catchscdic = obj;
                *stop = YES;
            }
        }];
        
        if (catchscdic) {
            [svbehar removeObject:catchscdic];
        }
        
        if (selsc) {
            [svBehaviorDic setObject:selsc forKey:@"catchSV"];
        }
        [svBehaviorDic setObject:svbehar forKey:@"otherSVBehaviorAr"];
    }
    
    return selsc;
}

- (BOOL)touchesShouldBegin:(NSSet<UITouch *> *)touches
                 withEvent:(UIEvent *)event
             inContentView:(UIView *)view {
    
    if (_lastScrollIsInner &&
        _currentScrollView &&
        self.bods_isDecelerating &&
        [view isKindOfClass:[UIControl class]] &&
        [self __findViewHierarchy:view] == 1) {
        //惯性Decelerating过程中，滑动内部捕获的sc时，需要响应内部sc以外的UIcontrol事件
        _theCtrWhenDecInner = (UIControl *)view;
        [_theCtrWhenDecInner sendActionsForControlEvents:UIControlEventTouchDown];
    }
    
    NSDictionary *setinfo = [self trySetupCurrentScrollViewWithContentView:view];
    UIView *thewebview = [setinfo objectForKey:@"webView"];
    _didTouchWebView = (nil != thewebview);
    
    return [super touchesShouldBegin:touches withEvent:event inContentView:view];
}

- (NSDictionary *)trySetupCurrentScrollViewWithContentView:(UIView *)view {
    _innerSVBehaviorInfo = nil;
    
    NSMutableDictionary *retdic = @{}.mutableCopy;
    
    NSMutableDictionary *svbehaviordic = @{}.mutableCopy;
    UIScrollView *selscv = [self __seekTargetScrollViewFrom:view svBehaviorDic:svbehaviordic];
    UIView *thewebview = [svbehaviordic objectForKey:@"webView"];
    
    if (nil != thewebview) {
        [retdic setObject:thewebview forKey:@"webView"];
        
        if (self.inhibitPanelForWebView) {
            return retdic;
        }
        
    }
    
    if (self.ignoreWebMulInnerScroll
        && thewebview) {
        //在webView中，且需要不影响多层可用的web内部scrollView
        NSArray<UIScrollView *> *nestscar =\
        [self __seekScrollViewMultipleNesting:selscv
                                      endView:thewebview
                                includeTarget:YES
                     judgeInnerSVBehaviorInfo:NO];
        if (nestscar.count >= 2) {
            //设置了ignoreWebMulInnerScroll，且发现web内有多层嵌套了，不捕获，不干涉，返回即可
            return retdic;
        }
    }
    
    if (svbehaviordic.count > 0) {
        if (self.dragScrollDelegate
            && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:catchAndPriorityInfo:)]) {
            [self.dragScrollDelegate dragScrollView:self catchAndPriorityInfo:svbehaviordic];
            selscv = [svbehaviordic objectForKey:@"catchSV"] ? : selscv;
        }
        
        NSArray<NSDictionary *> *otherSVBehaviorAr = svbehaviordic[@"otherSVBehaviorAr"];
        if ([otherSVBehaviorAr isKindOfClass:[NSArray class]]) {
            [otherSVBehaviorAr enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                UIScrollView *sv = [obj objectForKey:@"sv"];
                NSNumber *prioritynum = obj[@"priority"];
                if ([sv isKindOfClass:[UIScrollView class]]
                    && [prioritynum isKindOfClass:[NSNumber class]]) {
                    //优先级信息存储
                    [svbehaviordic setObject:prioritynum
                                      forKey:[NSString stringWithFormat:@"%p", sv]];
                }
            }];
        }
        
        _innerSVBehaviorInfo = svbehaviordic;
    }
    
    [self __setupCurrentScrollView:selscv];
    
    return retdic;
}

/*
 内部使用，用来计算图层位置
 -1 - self(0) - 1 - _currentScrollView(2) - 3
 */
- (NSInteger)__findViewHierarchy:(UIView *)view {
    NSInteger res = -1;
    
    for (UIView *targetbv = view; targetbv != nil; targetbv = targetbv.superview) {
        if (targetbv == self) {
            if (view == targetbv) {
                res = 0;
            } else {
                res = 1;
            }
            break;
        } else if (targetbv == _currentScrollView) {
            if (view == _currentScrollView) {
                res = 2;
            } else {
                res = 3;
            }
            break;
        }
    }
    return res;
}

//BODragScrollView本身不响应交互，只对内部embedview响应
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL res;
    if (self.embedView) {
        //兼容动画变化
        CALayer *emlayer = self.embedView.layer.presentationLayer ? : self.embedView.layer;
        CALayer *sflayer = self.layer;
        CGPoint innerpt = [sflayer convertPoint:point toLayer:emlayer];
        res = [self.embedView pointInside:innerpt withEvent:event];
    } else {
        res = NO;
    }
    
    return res;
}

/*
 滑动松开手指后的惯性过程中(isDecelerating)，
 如果又点击了一下scrollView，会发现此次点击会使scrollView惯性停止，同时引发现象：
 1.如果点击发生在UIControl、UIButton上，其不响应本次点击
 (touch事件不被调用，即使touchesShouldBegin:withEvent:inContentView:返回YES也没用；手势全部共存也没用)
 2.如果点击发生在WebView(UI和WK的某些网页都有出现)中，停止惯性的同时会触发webView内部的点击逻辑(和webView内部使用的gesture方式优化)
 
 为了解决上述中webView被多余响应一起其它惯性点击的响应问题，在hitTest中进行相应处理
 */
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.hidden
        && self.userInteractionEnabled
        && self.alpha > 0.01
        && self.embedView) {
        //兼容动画变化
        CALayer *emlayer = self.embedView.layer.presentationLayer ? : self.embedView.layer;
        CALayer *sflayer = self.layer;
        CGPoint innerpt = [sflayer convertPoint:point toLayer:emlayer];
        BOOL piev = [self.embedView pointInside:innerpt withEvent:event];
        if (piev) {
            UIView *htv = [self.embedView hitTest:innerpt withEvent:event];
            /*
             以下逻辑是为了防止多层scrollView嵌套时，或者内部嵌套webView时，惯性过程点击本应只是停止滑动，但触发了内部的响应
             这里监测到isScrollAnimating、isDecelerating时只响应scrollView，不响应内部其他view
             */
            if (event
                && (self.isScrollAnimating || self.bods_isDecelerating)
                && htv) {
                //惯性和动画滑动时
                if (_currentScrollView && _lastScrollIsInner) {
                    //若滑动的捕获sc内部
                    if ([self __findViewHierarchy:htv] > 2) {
                        NSArray<UIScrollView *> *svar =\
                        [self __seekScrollViewMultipleNesting:htv
                                                      endView:_currentScrollView
                                                includeTarget:YES
                                     judgeInnerSVBehaviorInfo:NO];
                        //点击内部不响应其内部内容，scrollView除外
                        if (svar.count > 0) {
                            return svar.firstObject;
                        } else {
                            return _currentScrollView;
                        }
                    } else {
                        //点击非捕获sc内，正常响应即可
                        return htv;
                    }
                } else {
                    //若滑动的自身，不响应惯性或动画中非scrollView的子内容，只停止本身的滑动
                    return [self __seekTargetScrollViewFrom:htv svBehaviorDic:nil] ? : self;
                }
            } else {
                //如果层级中有scrollView处于惯性过程，直接响应到该scrollView不响应内部
                for (UIResponder *theview = htv;
                     self != theview && nil != theview;
                     theview = theview.nextResponder) {
                    if ([theview isKindOfClass:[UIScrollView class]]) {
                        UIScrollView *thescrollv = (id)theview;
                        if (thescrollv.isDecelerating) {
                            return thescrollv;
                        }
                    }
                }
            }
            return htv;
        } else {
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)layoutSubviews {
    BOOL sizechange = !CGSizeEqualToSize(self.bounds.size, _lastLayoutBounds.size);
    CGRect prebounds = _lastLayoutBounds;
    _lastLayoutBounds = self.bounds;
    if ((sizechange || !_hasLayoutEmbedView)
        &&
        nil != _embedView) {
        BOOL newlayoutembed = (NO == _hasLayoutEmbedView);
        _hasLayoutEmbedView = YES;
        if (nil != _needsAnimatedToH) {
            __weak typeof(self) ws = self;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (nil == ws.needsAnimatedToH) {
                    return;
                }
                CGFloat needsath = ws.needsAnimatedToH.floatValue;
                ws.needsAnimatedToH = nil;
                if (!sf_uifloat_equal(needsath, ws.currDisplayH)) {
                    [ws scrollToDisplayH:needsath animated:YES completion:nil];
                }
            }];
        }
        CGRect embedrect = self.embedView.frame;
        CGSize cardsize = embedrect.size;
        CGFloat displayh;
        CGFloat mindh = (self.attachDisplayHAr.count > 0 ?
                         self.attachDisplayHAr.firstObject.floatValue
                         :
                         ((nil != self.minDisplayH) ? self.minDisplayH.floatValue : 66));
        if (nil != _needsDisplayH) {
            //有预置值
            displayh = _needsDisplayH.floatValue;
            _needsDisplayH = nil;
        } else {
            if (newlayoutembed) {
                //无预置情况下首次布局embedview，取最小值
                displayh = mindh;
            } else {
                //size变更布局
                displayh = CGRectGetHeight(prebounds) - (CGRectGetMinY(embedrect) - self.contentOffset.y);
            }
        }
        
        if (self.dragScrollDelegate && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:layoutEmbedView:firstLayout:willShowHeight:)]) {
            cardsize = [self.dragScrollDelegate dragScrollView:self
                                               layoutEmbedView:_embedView
                                                   firstLayout:newlayoutembed
                                                willShowHeight:&displayh];
            
            //有可能在上个代理方法里改变了attachDisplayHAr或minDisplayH的值
            mindh = (self.attachDisplayHAr.count > 0 ?
                     self.attachDisplayHAr.firstObject.floatValue
                     :
                     ((nil != self.minDisplayH) ? self.minDisplayH.floatValue : 66));
        }
        
        CGFloat sfw = CGRectGetWidth(self.bounds);
        CGFloat selfh = CGRectGetHeight(self.bounds);
        if (cardsize.height <= 0 || cardsize.width <= 0) {
            cardsize = [self.embedView sizeThatFits:CGSizeMake(sfw, CGFLOAT_MAX)];
        }
        
        if (cardsize.width <= 0) {
            cardsize.width = sfw;
        }
        
        if (cardsize.height <= 0) {
            cardsize.height = selfh;
        }
        
        embedrect.origin = CGPointMake((sfw - cardsize.width) * 0.5, 0);
        embedrect.size = cardsize;
        
        UIEdgeInsets inset = UIEdgeInsetsZero;
        inset.top = selfh - mindh;
        
        CGFloat maxdh = (self.attachDisplayHAr.count > 0 ?
                         self.attachDisplayHAr.lastObject.floatValue
                         :
                         cardsize.height);
        inset.bottom = MAX(maxdh - CGRectGetHeight(self.bounds), 0);
        
        [self innerSetting:^{
            self.bo_contentInset = inset;
            self.bo_contentSize = CGSizeMake(sfw, maxdh);
            self.bo_contentOffset = CGPointMake(0, -(selfh - displayh));
            [self setEmbedViewFrame:embedrect];
        }];
        
        [self forceReloadCurrInnerScrollView];
        
        //更新面板展示高度
        self.currDisplayH = CGRectGetHeight(self.bounds) - (CGRectGetMinY(_embedView.frame) - self.contentOffset.y);
    }
    
    [super layoutSubviews];
}

#pragma mark - 设置内部scrollview

- (void)setEmbedViewFrame:(CGRect)evFrame {
    if (!CGRectEqualToRect(self.embedView.frame, evFrame)) {
        CGSize embsz = self.embedView.bounds.size;
        if (!CGSizeEqualToSize(embsz, evFrame.size)) {
            //size不同就直接设置
            self.embedView.frame = evFrame;
        } else {
            //size相同时，只改center即可，防止设frame时触发其内部布局，比如embedView是个scrollView时，重设frame系统会更新其内部offset
            //重设center的位置变化有时也会触发系统会更新其内部但触发的几率比改size少
            CGPoint ocenter = self.embedView.center;
            CGPoint ncenter = CGPointMake(evFrame.origin.x + (embsz.width * self.embedView.layer.anchorPoint.x),
                                          evFrame.origin.y + (embsz.height * self.embedView.layer.anchorPoint.y));
            if (!CGPointEqualToPoint(ocenter, ncenter)) {
                self.embedView.center = ncenter;
            }
        }
    }
}

- (void)setCurrentSVContentOffset:(CGPoint)offset {
    if (!_currentScrollView) {
        return;
    }
    if (!CGPointEqualToPoint(_currentScrollView.contentOffset, offset)) {
        _currentScrollView.bo_contentOffset = offset;
        _lastSetInnerOSy = offset;
    }
}


- (void)setCurrentScrollView:(UIScrollView *)currentScrollView force:(BOOL)force {
    if (force) {
        [self __setupCurrentScrollView:currentScrollView];
    } else {
        if (_currentScrollView != currentScrollView) {
            [self __setupCurrentScrollView:currentScrollView];
        }
    }
}

- (void)__setupCurrentScrollView:(UIScrollView *)currentScrollView {
    [self __setupCurrentScrollView:currentScrollView type:0];
}

/*
 type:0 普通设置
 type: 1 内部scrollview的observer的设置，这种情况下不要bounce外部
 */
- (void)__setupCurrentScrollView:(UIScrollView *)currentScrollView
                            type:(NSInteger)setType {
#if DEBUG
    NSAssert(_embedView != nil, @"embedview should not be nil");
    if (![NSThread isMainThread]) {
        @throw [NSException exceptionWithName:@"Main Thread Checker"
                                       reason:@"Main Thread Checker: UI API called on a background thread: __setupCurrentScrollView:"
                                     userInfo:nil];
    }
#endif
    
    CGRect embedf = _embedView.frame;
    //embedView当前展示顶部距离本容器顶部的距离
    CGFloat embedcurrts = CGRectGetMinY(embedf) - self.contentOffset.y;
    
    CGSize contentsize = self.contentSize;
    CGPoint sfoffset = self.contentOffset;
    CGFloat sfh = CGRectGetHeight(self.bounds);
    BOOL issame = (currentScrollView == _currentScrollView);
    
    if (_currentScrollView) {
        //切换了scrollview：若原scrollview在bounces中，弹回正常区域
        //未切换：不做处理，延续位置
        if (nil == currentScrollView || currentScrollView != _currentScrollView) {
            CGPoint os = _currentScrollView.contentOffset;
            UIEdgeInsets cinset = sf_common_contentInset(_currentScrollView);
            if (os.y < -cinset.top) {
                //头部bounces
                os.y = -cinset.top;
                [_currentScrollView setContentOffset:os animated:YES];
                _lastSetInnerOSy = os;
            } else {
                CGFloat maxos = MAX((_currentScrollView.contentSize.height + cinset.bottom
                                     - CGRectGetHeight(_currentScrollView.bounds)),
                                    -cinset.top);
                if (os.y > maxos) {
                    //底部bounces
                    os.y = maxos;
                    [_currentScrollView setContentOffset:os animated:YES];
                    _lastSetInnerOSy = os;
                }
            }
            
            //如果设置过indictor dismiss indictor
            if (self.autoShowInnerIndictor) {
                [self __dismissIndictor:_currentScrollView];
            }
        }
        
        /*
         移除内部ScrollView
         */
        if (!issame) {
            if (self.currentScrollViewHasObserver) {
                [self __removeObserveForSc:_currentScrollView];
                self.currentScrollViewHasObserver = NO;
            }
            
            if (_needsRecoverScrollVAllowScrollToTop) {
                _currentScrollView.scrollsToTop = YES;
                _needsRecoverScrollVAllowScrollToTop = NO;
            }
            _currentScrollView = nil;
            super.decelerationRate = _curDecelerationRate;
        }
        
        //清空辅助计算的内容
        if (_innerSVAttInfCount > 0) {
            free(_innerSVAttInfAr);
            _innerSVAttInfAr = nil;
            _innerSVAttInfCount = 0;
        }
        _totalScrollInnerOSy = 0;
        _lastInnerSCSize = CGSizeZero;
        _lastSetInnerOSy = CGPointZero;
        _missAttachAndNeedsReload = 0;
        
        //本次是清空，没有新的currentScrollView设置，则清空innerSVBehaviorInfo相关信息
        if (!currentScrollView) {
            _innerSVBehaviorInfo = nil;
            [self __checkContentInset:nil];
        }
    }
    
    CGFloat maxdh = (self.attachDisplayHAr.count > 0 ?
                     self.attachDisplayHAr.lastObject.floatValue
                     :
                     CGRectGetHeight(embedf));
    contentsize.height = maxdh;
    [self innerSetting:^{
        self.bo_contentSize = contentsize;
    }];
    embedf.origin.y = 0;
    sfoffset.y = -embedcurrts;
    
    BOOL needssetinneroffset = NO;
    CGPoint spinneroffset = CGPointZero;
    
    if (nil != currentScrollView) {
        /*
         添加内部ScrollView
         */
        if (!issame) {
            _currentScrollView = currentScrollView;
            if (_currentScrollView.scrollsToTop) {
                _currentScrollView.scrollsToTop = NO;
                _needsRecoverScrollVAllowScrollToTop = YES;
            }
            if (!self.innerScrollViewFirst) {
                [self __addObserveForSc:_currentScrollView];
                self.currentScrollViewHasObserver = YES;
            }
        }
    }
    
    if (nil != currentScrollView
        && !self.innerScrollViewFirst) {
        //处理新捕获的scrollview
        
        //夹在_currentScrollView和embedView层级中间的嵌套scrollView
        NSMutableArray<UIScrollView *> *nestSvAr =\
        [self __seekScrollViewMultipleNesting:_currentScrollView
                                      endView:self
                                includeTarget:NO
                     judgeInnerSVBehaviorInfo:YES];
        //将捕获的scrollView以索引值为key存入
        [nestSvAr enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [_innerSVBehaviorInfo setObject:obj forKey:@(idx + 1)];
        }];
        
        _lastInnerSCSize = _currentScrollView.contentSize;
        
        CGFloat onepxiel = sf_getOnePxiel();
        UIEdgeInsets cinset = sf_common_contentInset(_currentScrollView);
        
        CGFloat innertotalsc = 0;
        CGFloat oriinnerosy = _currentScrollView.contentOffset.y;
        //当前内部一共滑了多远
        CGFloat innercursc = oriinnerosy + cinset.top;
        
        innertotalsc = (cinset.top
                        + _currentScrollView.contentSize.height
                        + cinset.bottom
                        - CGRectGetHeight(_currentScrollView.bounds));
        
        BOOL caninnerscroll;
        if (innertotalsc > 0) {
            //有可滑动区域
            caninnerscroll = YES;
        } else {
            //没有可正常滑动
            innertotalsc = 0;
            //根据是否可bounces判断内部是否可滑（进行bounces）
            caninnerscroll = (_currentScrollView.bounces && _currentScrollView.alwaysBounceVertical);
        }
        
        NSArray<NSDictionary *> *scinnerinfoar = nil;
        if (self.dragScrollDelegate && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:scrollBehaviorForInnerSV:)]) {
            scinnerinfoar = [self.dragScrollDelegate dragScrollView:self scrollBehaviorForInnerSV:_currentScrollView];
        }
        
        //可滑动，且没有获得delegate指定，若有prefDragInnerScrollDisplayH指定，则从prefDragInnerScrollDisplayH指定位置开始滑动
        if (caninnerscroll
            && !scinnerinfoar
            && nil != self.prefDragInnerScrollDisplayH) {
            CGFloat beginOffsetY = -cinset.top;
            CGFloat endOffsetY = (innertotalsc > 0) ? (innertotalsc - beginOffsetY) : beginOffsetY;
            scinnerinfoar = @[
                @{
                    @"displayH": self.prefDragInnerScrollDisplayH,
                    @"beginOffsetY": @(beginOffsetY),
                    @"endOffsetY": @(endOffsetY)
                }
            ];
        }
        
        /*
         innerinfoar需要容纳所有吸附点
         其数量：
         当只有一层，没有多层嵌套(nestSvAr)时，与指定的数量相同即可，若无指定，只有一个吸附点，
         加上有可能为了prefDragInnerScroll属性添加上下区域的临时缓存触发点故最小容量为2
         
         当有多层嵌套(nestSvAr)时，每一层有可能在上一层中间滑动，上半截、中间自己，和下半截最多分成3截，
         所以做大数量是嵌套层级*3
         */
        NSInteger maxarcount = MAX(scinnerinfoar.count, 2);
        if (nestSvAr.count > 0) {
            maxarcount = MAX(maxarcount, nestSvAr.count * 3);
        }
        BODragScrollAttachInfo *innerinfoar =\
        (BODragScrollAttachInfo *)malloc(maxarcount * sizeof(BODragScrollAttachInfo));
        BOOL innerinfoarhascompmem = NO;
        NSInteger innerinfocount = 0;
        
        BOOL specialinnersc = NO;
        //内部scrollView不再其应该滑动位置，但contentoffset不相符，其应该的滑动位置在当前位置：向下-1  向上1  没有是0，不确定是3
        NSInteger innerscmayinother = 0;
        NSInteger findwhichidx = -1;
        
        if (caninnerscroll) {
            //内部可滑动
            
            CGFloat embedmaxts = self.contentInset.top;
            
            CGFloat maxdh = (self.attachDisplayHAr.count > 0 ?
                             self.attachDisplayHAr.lastObject.floatValue
                             :
                             CGRectGetHeight(embedf));
            
            CGFloat embedmints = MIN(sfh - maxdh,
                                     embedmaxts);
            
#define m_topext (embedcurrts - embedmaxts)
#define m_topextinner (-innercursc)
#define m_bottomext (embedmints - embedcurrts)
#define m_bottomextinner (innercursc - innertotalsc)
            
            CGFloat topbounces = 0;
            CGFloat bottombounces = 0;
            
            //计算innercursc  embedcurrts  topbounces  bottombounces
            if (0 == setType) {
                if (m_topext > 0 || m_topextinner > 0) {
                    //内部或者外部卡片的top bounces了
                    BOOL bouncescard = (self.allowBouncesCardTop &&
                                        (self.prefBouncesCardTop || !_currentScrollView.bounces));
                    if (self.forceBouncesInnerTop) {
                        bouncescard = NO;
                    }
                    
                    if (bouncescard) {
                        //优先bounces 卡片
                        if (m_topext > 0) {
                            //外部拉力转移到内部
                            innercursc -= m_topext;
                            embedcurrts = embedmaxts;
                        }
                        
                        //若内部无法中和拉力，剩余的拉力转移到外部
                        if (m_topextinner > 0) {
                            embedcurrts += m_topextinner;
                            innercursc = 0;
                        }
                        
                        topbounces = MAX(m_topext, 0);
                    } else {
                        //优先bounces内部
                        if (m_topextinner > 0) {
                            //内部拉力转移到外部
                            embedcurrts += m_topextinner;
                            innercursc = 0;
                        }
                        
                        //若外部无法中和拉力，剩余的拉力转移到内部
                        if (m_topext > 0) {
                            innercursc -= m_topext;
                            embedcurrts = embedmaxts;
                        }
                        topbounces = MAX(m_topextinner, 0);
                    }
                }
                
                if (m_bottomext > 0 || m_bottomextinner > 0) {
                    //内部或者外部卡片的bottom bounces了
                    BOOL bouncescard = (self.allowBouncesCardBottom &&
                                        (self.prefBouncesCardBottom || !_currentScrollView.bounces));
                    if (bouncescard) {
                        //优先bounces外部
                        
                        if (m_bottomext > 0) {
                            //外部bounces转移到内部
                            innercursc += m_bottomext;
                            embedcurrts = embedmints;
                        }
                        
                        //若内部无法中和拉力，剩余的拉力转移到外部
                        if (m_bottomextinner > 0) {
                            embedcurrts -= m_bottomextinner;
                            innercursc = innertotalsc;
                        }
                        
                        bottombounces = MAX(m_bottomext, 0);
                    } else {
                        //优先bounces内部
                        if (m_bottomextinner > 0) {
                            //内部bounces转移到外部
                            embedcurrts -= m_bottomextinner;
                            innercursc = innertotalsc;
                        }
                        
                        //若外部无法中和拉力，剩余的拉力转移到内部
                        if (m_bottomext > 0) {
                            //外部bounces转移到内部
                            innercursc += m_bottomext;
                            embedcurrts = embedmints;
                        }
                        
                        bottombounces = MAX(m_bottomextinner, 0);
                    }
                }
            }
            
            BOOL innerinfocomplete = NO; //初始化内部scrollView滑动是否完成
            
            CGFloat curmaydh = (sfh - embedcurrts); //计算完后当前展示高度
            if (scinnerinfoar.count > 0) {
                //若指定了内部的滑动行为
                
                BODragScrollAttachInfo lastatinfo;
                CGFloat infoartotalsc = 0;
                BOOL haslastinfo = NO;
                
                CGFloat beginOffsetY = -cinset.top;
                for (NSInteger innerdicidx = 0; innerdicidx < scinnerinfoar.count; innerdicidx++) {
                    NSDictionary *innerscdic = scinnerinfoar[innerdicidx];
                    NSNumber *dhval = [innerscdic objectForKey:@"displayH"];
                    if (nil == dhval) {
                        continue;
                    }
                    
                    //若beginOffsetY、endOffsetY没有填值，进行默认填充
                    NSNumber *beginval = [innerscdic objectForKey:@"beginOffsetY"];
                    //首个、没有填beginOffsetY则默认从最顶部开始
                    if (0 == innerdicidx
                        && nil == beginval) {
                        beginval = @(beginOffsetY);
                    }
                    
                    NSNumber *endval = [innerscdic objectForKey:@"endOffsetY"];
                    //最后一个、没有填endval，则默认到底
                    if (scinnerinfoar.count - 1 == innerdicidx
                        && nil == endval) {
                        endval = @((innertotalsc > 0) ? (innertotalsc - beginOffsetY) : beginOffsetY);
                    }
                    
                    //还没有值，此数据非法，执行抛弃
                    if ((nil == beginval)
                        || (nil == endval)) {
                        continue;
                    }
                    
                    CGFloat infodh = dhval.floatValue;
                    CGFloat infbegin = beginval.floatValue;
                    CGFloat infend = endval.floatValue;
                    
                    //有效判断,不需要判断了吧 浪费资源 由外部保障传入即可
                    //                    if (infend <= infbegin) {
                    //                        //击毁
                    //                        break;
                    //                    }
                    //
                    //                    if (lastdhval) {
                    //                        if (infodh <= lastdhval.floatValue) {
                    //                            //击毁
                    //                            break;
                    //                        }
                    //                    }
                    //                    lastdhval = dhval;
                    //                    if (lastendval) {
                    //                        if (infbegin < lastendval.floatValue) {
                    //                            //击毁
                    //                            break;
                    //                        }
                    //                    }
                    //                    lastendval = endval;
                    
                    CGFloat inflength = infend - infbegin;
                    CGFloat infosy = infoartotalsc + infodh - sfh;
                    BODragScrollAttachInfo atinf =\
                    (BODragScrollAttachInfo){-1, infodh, infosy, YES, infbegin, infend, infosy + inflength};
                    if (haslastinfo && atinf.dragSVOffsetY <= lastatinfo.dragSVOffsetY) {
                        //数据非法
                        continue;
                    }
                    
                    if (findwhichidx < 0) {
                        CGFloat curinnerosy = innercursc - cinset.top;
                        if (infodh + onepxiel >= curmaydh) {
                            findwhichidx = innerdicidx;
                            
                            //判断当前内部滑动位置是否合法，若不在合适位置，进行复位
                            //scinnerar情况下暂不考虑autoResetInnerSVOffsetWhenAttachMiss 可后续再扩展
                            if (curmaydh < infodh - onepxiel) {
                                if (curinnerosy > infbegin) {
                                    innercursc = infoartotalsc;
                                    innerscmayinother = 1;
                                } else {
                                    if (haslastinfo) {
                                        innercursc = infoartotalsc;
                                    } else {
                                        innercursc = 0;
                                    }
                                }
                            } else if (curmaydh <= infodh + onepxiel) {
                                if (curinnerosy < infbegin) {
                                    innercursc = infoartotalsc;
                                } else if (curinnerosy > infend) {
                                    if (innerdicidx < scinnerinfoar.count - 1) {
                                        innercursc = infoartotalsc + inflength;
                                    } else {
                                        innercursc = infoartotalsc + (curinnerosy - infbegin);
                                    }
                                } else {
                                    innercursc = infoartotalsc + (curinnerosy - infbegin);
                                    specialinnersc = YES;
                                }
                            }
                        } else if (scinnerinfoar.count - 1 == innerdicidx) {
                            findwhichidx = innerdicidx;
                            if (curinnerosy < infend) {
                                innercursc = infoartotalsc + inflength;
                                innerscmayinother = -1;
                            } else {
                                innercursc = infoartotalsc + (curinnerosy - infbegin);
                            }
                        }
                    }
                    
                    //插入内部滑动点
                    innerinfoar[innerinfocount] = atinf;
                    innerinfocount++;
                    infoartotalsc += inflength;
                    lastatinfo = atinf;
                    if (!haslastinfo) {
                        haslastinfo = YES;
                    }
                }
                
                innertotalsc = infoartotalsc;
                
                if (innerinfocount > 0) {
                    //获得了有效的内部滑动行为，内部滑动行为加载完成
                    innerinfocomplete = YES;
                }
            }
            
            //没有指定的行为，启用智能判定
            if (!innerinfocomplete) {
                // 内部scrollView顶部距离embedView顶部的距离
                CGFloat dyembedtosc =\
                [_embedView convertRect:_currentScrollView.frame fromView:_currentScrollView.superview].origin.y;
                CGFloat curscts = embedcurrts + dyembedtosc;
                CGFloat scheight = CGRectGetHeight(_currentScrollView.frame);
                //开始滑动内部时，内部scrollView.top距离DragScrollView可展示局域顶部的距离
                CGFloat scinnerts = curscts;
                
//#if DEBUG
//                CGFloat scmints = embedmints + dyembedtosc;
//                //内部bounces时，外部位置需要在最上/下（之上的逻辑需要处理完这种情况）
//                if (innercursc < 0) {
//                    CGFloat scmaxts = embedmaxts + dyembedtosc;
//                    NSAssert(sf_uifloat_equal(curscts, scmaxts), @"innercursc < 0, curscts == scmaxts");
//                } else if (innercursc > innertotalsc) {
//                    NSAssert(sf_uifloat_equal(curscts, scmints), @"innercursc < 0, curscts(%@) == scmints(%@)", @(curscts), @(scmints));
//                }
//#endif
                
                //是否需要根据scinnerts自动添加单个可滑动内部的位置
                BOOL needsaddoneinnerscroll = NO;
                
                if (self.attachDisplayHAr.count > 0) {
                    //有吸附点
                    NSMutableArray<NSNumber *> *theattachar = self.attachDisplayHAr.mutableCopy;
                    if (self.forceBouncesInnerTop) {
                        NSInteger theidx = bo_findIdxInFloatArrayByValue(theattachar, curmaydh, YES, NO);
                        CGFloat thedh = theattachar[theidx].floatValue;
                        if (thedh == curmaydh
                            && theidx > 0) {
                            [theattachar removeObjectsInRange:NSMakeRange(0, theidx)];
                        }
                    }
                    [self __checkContentInset:theattachar];
                    //是否需要使用结合吸附点的指定判定
                    BOOL needssmartadd = NO;
                    if (self.prefDragInnerScroll) {
                        //指定从当前开始滑
                        NSInteger theidx = bo_findIdxInFloatArrayByValue(theattachar, curmaydh, NO, NO);
                        //上面已经判断了theattachar.count > 0，bo_findIdxInFloatArrayByValue返回的一定是合法值
                        CGFloat thedh = theattachar[theidx].floatValue;
                        //当前面板是否在吸附点上
                        BOOL currinattach = sf_uifloat_equal(curmaydh, thedh);
                        if (currinattach) {
                            //默认当前开始滑即可
                            needssmartadd = NO;
                            needsaddoneinnerscroll = YES;
                        } else {
                            //不在吸附点，不滑，下一个到达的吸附点再滑
//                            if (innercursc < onepxiel) {
//                                NSInteger nextidx = theidx + 1;
//
//                                if (nextidx < theattachar.count) {
//                                    needssmartadd = NO;
//                                    needsaddoneinnerscroll = YES;
//
//                                    CGFloat nextdh = theattachar[nextidx].floatValue;
//                                    scinnerts = sfh - nextdh + dyembedtosc;
//                                } else {
//                                    //数值非法, 走智能判定
//                                    needssmartadd = YES;
//                                    needsaddoneinnerscroll = YES;
//                                }
//
//                            } else if (innercursc > innertotalsc - onepxiel) {
//                                needssmartadd = NO;
//                                needsaddoneinnerscroll = YES;
//
//                                scinnerts = sfh - thedh + dyembedtosc;
//                            } else {
                                //在中间
                                //在上、在下都认为在中间，然后两边都加滑动内部的区域，待到区域后会重新加载
                                NSInteger nextidx = theidx + 1;
                                
                                if (nextidx < theattachar.count) {
                                    needssmartadd = NO;
                                    needsaddoneinnerscroll = NO;
                                    
                                    innerscmayinother = 3;
                                    
                                    CGFloat firstoffset = thedh - sfh; //开始滑动内部时的offset.y
                                    firstoffset = MAX(MIN(-embedmints, firstoffset), -embedmaxts);
                                    BODragScrollAttachInfo scinf =\
                                    (BODragScrollAttachInfo){-1,
                                        thedh, firstoffset,
                                        YES, -cinset.top, -cinset.top + innercursc,
                                        firstoffset + innercursc};
                                    innerinfoar[0] = scinf;
                                    
                                    CGFloat nextdh = theattachar[nextidx].floatValue;
                                    CGFloat nextoffset = firstoffset + innercursc + (nextdh - thedh); //开始滑动内部时的offset.y
                                    BODragScrollAttachInfo scinf2 =\
                                    (BODragScrollAttachInfo){-1,
                                        nextdh, nextoffset,
                                        YES, -cinset.top + innercursc, -cinset.top + innertotalsc,
                                        nextoffset + (innertotalsc - innercursc)};
                                    innerinfoar[1] = scinf2;
                                    
                                    innerinfocount = 2;
                                } else {
                                    //数值非法, 走智能判定
                                    needssmartadd = YES;
                                    needsaddoneinnerscroll = YES;
                                }
//                            }
                            
                        }
                        
                    } else {
                        needssmartadd = YES;
                        needsaddoneinnerscroll = YES;
                    }
                    
                    if (needssmartadd) {
                        BOOL findbeg = NO; //是否找到开始滑动内部时的位置

                        CGFloat beginscdh = 0;
                        CGFloat totalinnerscdh = dyembedtosc + scheight;
                        NSInteger theidx = bo_findIdxInFloatArrayByValue(theattachar, curmaydh, NO, YES);
                        CGFloat minshowrate = 0.7; //滑动内部时，内部至少展示70%（视觉友好），这个数值根据需要再调吧
                        for (NSInteger uidx = theidx; uidx < theattachar.count; uidx++) {
                            CGFloat thedh = theattachar[uidx].floatValue;
                            BOOL thisfind = NO;
                            //找到能超过内部scrollview的吸附店
                            CGFloat innerscshowheight = thedh - dyembedtosc;
                            if (innerscshowheight > 0
                                && scheight > 0
                                && (innerscshowheight / scheight) >= minshowrate) {
                                thisfind = YES;
                                //有一个吸附点可保证内部scrollView至少展示五分之一（根据需要调整吧），可以作为开始内部滑动的点
                                beginscdh = thedh;
                                findbeg = YES;
                            }
                            
                            if (thisfind) {
                                if (self.prefDragCardWhenExpand) {
                                    if (innerscshowheight < scheight - onepxiel) {
                                        //没展示完全
                                        continue;
                                    } else {
                                        if (uidx < theattachar.count - 1) {
                                            //还有下一个
                                            CGFloat nextdh = theattachar[uidx + 1].floatValue;
                                            CGFloat nextinnerscshowheight = nextdh - dyembedtosc;
                                            if (nextinnerscshowheight - sfh <= 0) {
                                                //下一个吸附点依然没有让内部区域超出
                                                continue;
                                            }
                                        }
                                        //展示完全了
                                        break;
                                    }
                                } else {
                                    //找到一个就好
                                    break;
                                }
                            }
                        }
                        
                        
                        if (!findbeg
                            && scheight > 0) {
                            NSInteger theminidx = bo_findIdxInFloatArrayByValue(theattachar, totalinnerscdh, NO, NO);
                            CGFloat themindh = theattachar[theminidx].floatValue;
                            CGFloat showheighrate = (themindh - dyembedtosc) / scheight;
                            if (showheighrate >= minshowrate) {
                                beginscdh = themindh;
                                findbeg = YES;
                            }
                        }
                        
                        if (findbeg) {
                            CGFloat shouldscbgts = sfh - beginscdh + dyembedtosc;
                            if (curscts < (shouldscbgts - onepxiel)) {
                                if (innercursc < (innertotalsc - onepxiel)) {
                                    if (_forceResetWhenScroll) {
                                        if (self.allowInnerSVWhenAttachMiss
                                            || self.prefDragCardWhenExpand) {
                                            //从当前开始滑
                                            beginscdh = curmaydh;
                                            shouldscbgts = sfh - beginscdh + dyembedtosc;
                                        } else {
                                            innercursc = innertotalsc;
                                        }
                                    } else {
                                        if (self.autoResetInnerSVOffsetWhenAttachMiss) {
                                            innercursc = innertotalsc;
                                        } else {
                                            //innerscmayinother时 innercursc虽然设置但不会被实际改变，只会用作计算整体的offset
                                            innercursc = innertotalsc;
                                            innerscmayinother = -1;
                                        }
                                    }
                                    
                                }
                                
                            } else if (curscts > (shouldscbgts + onepxiel)) {
                                if (innercursc > onepxiel) {
                                    if (_forceResetWhenScroll) {
                                        if (self.allowInnerSVWhenAttachMiss
                                            || self.prefDragCardWhenExpand) {
                                            //从当前开始滑
                                            beginscdh = curmaydh;
                                            shouldscbgts = sfh - beginscdh + dyembedtosc;
                                        } else {
                                            innercursc = 0;
                                        }
                                    } else {
                                        if (self.autoResetInnerSVOffsetWhenAttachMiss) {
                                            innercursc = 0;
                                        } else {
                                            if (self.prefDragCardWhenExpand) {
                                                innercursc = 0;
                                                innerscmayinother = 1;
                                            } else {
                                                if (self.allowInnerSVWhenAttachMiss) {
                                                    //从当前开始滑
                                                    beginscdh = curmaydh;
                                                    shouldscbgts = sfh - beginscdh + dyembedtosc;
                                                } else {
                                                    //innerscmayinother时 innercursc虽然设置但不会被实际改变，只会用作计算整体的offset
                                                    innercursc = 0;
                                                    innerscmayinother = 1;
                                                }
                                            }
                                            
                                        }
                                    }
                                    
                                }
                                
                            } else {
                                specialinnersc = YES;
                            }
                            
                            scinnerts = shouldscbgts;
                        }
                    }
                    
                } else {
                    //没有指定吸附点
                    
                    if (self.prefDragInnerScroll) {
                        //默认从当前开始滑动
                    } else if (self.prefDragCardWhenExpand) {
                        //指定优先拖拽整体，再滑动内部
                        //等embed滑到最大或者到屏幕顶时开始滑动内部
                        scinnerts = MAX(embedmints + dyembedtosc, 0.f);
                    }
                    
                }
                
                if (needsaddoneinnerscroll) {
                    CGFloat bofis = dyembedtosc - scinnerts; //开始滑动内部时的offset.y
                    bofis = MAX(MIN(-embedmints, bofis), -embedmaxts);
                    BODragScrollAttachInfo scinf =\
                    (BODragScrollAttachInfo){-1,
                        sfh + bofis, bofis,
                        YES, -cinset.top, -cinset.top + innertotalsc,
                        bofis + innertotalsc};
                    //只有一个内部滑动位置
                    innerinfoar[0] = scinf;
                    innerinfocount = 1;
                }
                
                //已经是最后一层了，一定保障innerinfocomplete加载完成，后面没有判断了，不需要再管这个标志位了，若后续还要加逻辑可恢复这行
                //                innerinfocomplete = YES;
            }
            
            if (innerinfocount > 0) {
                __block CGFloat nesttotalsc = 0;
                //nesting begin
                if (1 == innerinfocount
                    && nestSvAr.count > 0) {
                    //只指定了一个滑动区间，且有多层嵌套scrollView，进行多层滑动交互合并
                    BODragScrollAttachInfo baseainfo = innerinfoar[0];
                    
                    [nestSvAr enumerateObjectsUsingBlock:^(UIScrollView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        UIEdgeInsets onenestinset = sf_common_contentInset(obj);
                        CGFloat sctatol = (onenestinset.top
                                           + obj.contentSize.height
                                           + onenestinset.bottom
                                           - CGRectGetHeight(obj.bounds));
                        nesttotalsc += sctatol;
                    }];
                    
                    CGFloat remainnestsc = innertotalsc + nesttotalsc;
                    CGFloat pa = baseainfo.dragSVOffsetY;
                    CGFloat pb = baseainfo.dragSVOffsetY2 + nesttotalsc;
                    NSMutableArray<NSValue *> *infomuar = @[].mutableCopy;
                    //当前在infomuar的填充位置
                    NSUInteger fillidx = 0;
                    //加进去一起遍历
                    [nestSvAr insertObject:_currentScrollView atIndex:0];
                    for (NSInteger iidx = nestSvAr.count - 1;
                         iidx >= 0;
                         iidx--) {
                        UIScrollView *thesv = nestSvAr[iidx];
                        UIEdgeInsets onenestinset = sf_common_contentInset(thesv);
                        CGFloat thetatol = (onenestinset.top
                                            + thesv.contentSize.height
                                            + onenestinset.bottom
                                            - CGRectGetHeight(thesv.bounds));
                        remainnestsc -= thetatol;
                        UIScrollView *nextsv = nil;
                        if (iidx > 0) {
                            nextsv = nestSvAr[iidx - 1];
                            UIView *nextsvsuperview = nextsv.superview;
                            if (!nextsvsuperview) {
                                continue;
                            }
                            
                            //下一级的sv在当前sv中的位置
                            CGRect nextsvfmfromthesv = [thesv convertRect:nextsv.frame fromView:nextsvsuperview];
                            
                            CGFloat thesv_currsc = thesv.contentOffset.y + onenestinset.top;
                            //下一级已展示完全，且当前已经滑动过了
                            if (thesv_currsc > onepxiel
                                && (thesv.contentOffset.y + CGRectGetHeight(thesv.bounds)) >= CGRectGetMaxY(nextsvfmfromthesv)) {
                                //已经滑动过了，以当前状态为准
                                if (thesv_currsc >= thetatol - onepxiel) {
                                    //先滑当前
                                    BODragScrollAttachInfo theattinfo =\
                                    ((BODragScrollAttachInfo){iidx,
                                        baseainfo.displayH,
                                        pa,
                                        YES,
                                        -onenestinset.top,
                                        thetatol - onenestinset.top,
                                        pa + thetatol});
                                    pa = theattinfo.dragSVOffsetY2;
                                    [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                    fillidx += 1;
                                } else {
                                    //下一个在中间
                                    //先滑当前，再滑下一个，再滑当前
                                    BODragScrollAttachInfo theattinfo =\
                                    ((BODragScrollAttachInfo){iidx,
                                        baseainfo.displayH,
                                        pa,
                                        YES,
                                        -onenestinset.top,
                                        thesv.contentOffset.y,
                                        pa + thesv_currsc});
                                    pa = theattinfo.dragSVOffsetY2;
                                    [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                    fillidx += 1;
                                    
                                    CGFloat remainscroll = thetatol - thesv_currsc;
                                    BODragScrollAttachInfo theattinfo2 =\
                                    ((BODragScrollAttachInfo){iidx,
                                        baseainfo.displayH,
                                        pb - remainscroll,
                                        YES,
                                        thesv_currsc,
                                        thetatol - onenestinset.top,
                                        pb});
                                    pb = pb - remainscroll;
                                    [infomuar insertObject:[NSValue value:&theattinfo2 withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                }
                                
                                continue;
                            }
                            
                            if (CGRectGetMinY(nextsvfmfromthesv) <= -onenestinset.top + onepxiel) {
                                //在展示区域的顶部，先滑next再滑当前，所以在后边插入当前，fillidx不变，继续遍历
                                BODragScrollAttachInfo theattinfo =\
                                ((BODragScrollAttachInfo){iidx,
                                    baseainfo.displayH,
                                    pb - thetatol,
                                    YES,
                                    -onenestinset.top,
                                    thetatol - onenestinset.top,
                                    pb});
                                pb = theattinfo.dragSVOffsetY;
                                [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                            } else if (CGRectGetMaxY(nextsvfmfromthesv) >= thesv.contentSize.height + onenestinset.bottom - onepxiel) {
                                //在展示区域的底部，先滑当前再滑下一个，所以插入当前，fillidx增加，继续遍历
                                BODragScrollAttachInfo theattinfo =\
                                ((BODragScrollAttachInfo){iidx,
                                    baseainfo.displayH,
                                    pa,
                                    YES,
                                    -onenestinset.top,
                                    thetatol - onenestinset.top,
                                    pa + thetatol});
                                pa = theattinfo.dragSVOffsetY2;
                                [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                fillidx += 1;
                            } else {
                                //在中间
                                //底部长出多少
                                CGFloat bottomexp = thesv.contentSize.height + onenestinset.bottom - CGRectGetMaxY(nextsvfmfromthesv);
                                CGFloat topext = CGRectGetHeight(thesv.bounds) - (bottomexp + CGRectGetHeight(nextsvfmfromthesv));
                                if (topext + onepxiel >= 0) {
                                    //展示区域可以把下一个sv全展示，先滑当前即可
                                    BODragScrollAttachInfo theattinfo =\
                                    ((BODragScrollAttachInfo){iidx,
                                        baseainfo.displayH,
                                        pa,
                                        YES,
                                        -onenestinset.top,
                                        thetatol - onenestinset.top,
                                        pa + thetatol});
                                    pa = theattinfo.dragSVOffsetY2;
                                    [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                    fillidx += 1;
                                } else {
                                    
                                    //先滑当前到下一个sv可视最大，再滑下一个，再滑当前
                                    CGFloat minnexty = CGRectGetMinY(nextsvfmfromthesv);
                                    CGFloat prescroll = onenestinset.top + minnexty;
                                    BODragScrollAttachInfo theattinfo =\
                                    ((BODragScrollAttachInfo){iidx,
                                        baseainfo.displayH,
                                        pa,
                                        YES,
                                        -onenestinset.top,
                                        minnexty,
                                        pa + prescroll});
                                    pa = theattinfo.dragSVOffsetY2;
                                    [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                    fillidx += 1;
                                    
                                    CGFloat remainscroll = thetatol - prescroll;
                                    BODragScrollAttachInfo theattinfo2 =\
                                    ((BODragScrollAttachInfo){iidx,
                                        baseainfo.displayH,
                                        pb - remainscroll,
                                        YES,
                                        minnexty,
                                        thetatol - onenestinset.top,
                                        pb});
                                    pb = pb - remainscroll;
                                    [infomuar insertObject:[NSValue value:&theattinfo2 withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                                }
                            }
                        } else {
                            //iidx=0时为currScrollView，BODragScrollAttachInfo的scrollViewIdx用-1表示currScrollView，0用来表示无。
                            BODragScrollAttachInfo theattinfo =\
                            ((BODragScrollAttachInfo){-1,
                                baseainfo.displayH,
                                pa,
                                YES,
                                -onenestinset.top,
                                thetatol - onenestinset.top,
                                pa + thetatol});
                            [infomuar insertObject:[NSValue value:&theattinfo withObjCType:@encode(BODragScrollAttachInfo)] atIndex:fillidx];
                            fillidx += 1;
                        }
                        
                    }
                    
                    if (infomuar.count > 0) {
                        for (NSInteger iidx = 0; iidx < infomuar.count; iidx++) {
                            BODragScrollAttachInfo theinfo;
                            [infomuar[iidx] getValue:&theinfo];
                            innerinfoar[iidx] = theinfo;
                        }
                        innerinfocount = infomuar.count;
                    }
                }
                //nesting end
                
                contentsize.height = maxdh + innertotalsc + nesttotalsc;
                _totalScrollInnerOSy = innertotalsc + nesttotalsc;
                
                _innerSVAttInfAr = innerinfoar;
                innerinfoarhascompmem = YES;
                _innerSVAttInfCount = innerinfocount;
                
                if (innerinfocount == 1) {
                    BODragScrollAttachInfo mininf = innerinfoar[0];
                    _minScrollInnerOSy = mininf.dragSVOffsetY;
                    _maxScrollInnerOSy = mininf.dragSVOffsetY2;
                } else if (innerinfocount > 1) {
                    BODragScrollAttachInfo mininf = innerinfoar[0];
                    BODragScrollAttachInfo maxinf = innerinfoar[innerinfocount - 1];
                    _minScrollInnerOSy = mininf.dragSVOffsetY;
                    _maxScrollInnerOSy = maxinf.dragSVOffsetY2;
                } else {
                    //error 不应发生
                }
            }
            
            //innercursc  embedcurrts  topbounces  bottombounces
            CGPoint inneroffset = _currentScrollView.contentOffset;
            CGFloat tatolsc = innercursc;
            if (_innerSVAttInfCount > 0) {
                //设置当前内部inneroffset.y的值
                CGFloat addtotalsc = 0;
                for (NSInteger infoidx = 0; infoidx < _innerSVAttInfCount; infoidx++) {
                    BODragScrollAttachInfo theinfo = _innerSVAttInfAr[infoidx];
                    UIScrollView *theinfosv = [self __obtainScrollViewWithIdx:theinfo.scrollViewIdx];
                    if (theinfosv != _currentScrollView) {
                        tatolsc += MAX(MIN(theinfosv.contentOffset.y, theinfo.innerOffsetB) - theinfo.innerOffsetA, 0.f);
                        continue;
                    }
                    
                    CGFloat infodur = theinfo.innerOffsetB - theinfo.innerOffsetA;
                    if (addtotalsc + infodur > innercursc) {
                        inneroffset.y = theinfo.innerOffsetA + innercursc - addtotalsc;
                        break;
                    } else {
                        addtotalsc += infodur;
                    }
                    
                    if (infoidx == _innerSVAttInfCount - 1) {
                        inneroffset.y = theinfo.innerOffsetB + innercursc - addtotalsc;
                        break;
                    }
                }
            }
            
            BOOL hasbounces = NO;
            if (topbounces > 0) {
                sfoffset.y = -self.contentInset.top - topbounces;
                embedf.origin.y = sfoffset.y + embedcurrts;
                
                hasbounces = YES;
            } else if (bottombounces > 0) {
                CGFloat maxosy = MAX(contentsize.height + self.contentInset.bottom - sfh,
                                     -self.contentInset.top);
                sfoffset.y = maxosy + bottombounces;
                embedf.origin.y = sfoffset.y + embedcurrts;
                
                hasbounces = YES;
            } else {
                embedf.origin.y = tatolsc;
                sfoffset.y = embedf.origin.y - embedcurrts;
            }
            
            if ((0 != innerscmayinother)
                && !hasbounces
                && !specialinnersc
                && (_prefDragInnerScroll ||
                    (!_autoResetInnerSVOffsetWhenAttachMiss
                     && !_forceResetWhenScroll))) {
                _missAttachAndNeedsReload = innerscmayinother;
            }
            
            needssetinneroffset = YES;
            spinneroffset = inneroffset;
        }
        
        if (!innerinfoarhascompmem) {
            //如果以上流程没有把innerinfoar的内存合理托管或者释放，在此释放
            free(innerinfoar);
            //已经是最后一层了，一定保障innerinfoarhascompmem为YES，后面没有判断了，不需要再管这个标志位了，若后续还要加逻辑可恢复这行
            //            innerinfoarhascompmem = YES;
        }
    }
    
    [self innerSetting:^{
        self.bo_contentSize = contentsize;
        [self setEmbedViewFrame:embedf];
        self.bo_contentOffset = sfoffset;
        
        if (needssetinneroffset
            && 0 == self->_missAttachAndNeedsReload) {
            [self setCurrentSVContentOffset:spinneroffset];
        }
    }];
}

- (void)__dismissIndictor:(UIScrollView *)scrollView {
    UIView *indicv = [scrollView viewWithTag:sf_indictor_tag];
    if (indicv) {
        [UIView animateWithDuration:0.3 delay:0.7
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            indicv.alpha = 0;
        }
                         completion:nil];
    }
}

#pragma mark - 监听内部scrollView的contentSize、contentInset、frame的变化
static void *sf_observe_context = "sf_observe_context";

- (void)__addObserveForSc:(UIScrollView *)scrollView {
    if (!scrollView) {
        return;
    }
    
    BOOL needadjustedContentInset = YES;
    if (@available(iOS 11.0, *)) {
    } else {
        needadjustedContentInset = NO;
    }
    
    [scrollView addObserver:self
                 forKeyPath:@"contentSize"
                    options:NSKeyValueObservingOptionNew
                    context:sf_observe_context];
    [scrollView addObserver:self
                 forKeyPath:@"contentInset"
                    options:NSKeyValueObservingOptionNew
                    context:sf_observe_context];
    if (needadjustedContentInset) {
        [scrollView addObserver:self
                     forKeyPath:@"adjustedContentInset"
                        options:NSKeyValueObservingOptionNew
                        context:sf_observe_context];
    }
    
    scrollView.bo_dragScrollView = self;
}

- (void)__removeObserveForSc:(UIScrollView *)scrollView {
    if (!scrollView) {
        return;
    }
    
    BOOL needadjustedContentInset = YES;
    if (@available(iOS 11.0, *)) {
    } else {
        needadjustedContentInset = NO;
    }
    
    [scrollView removeObserver:self forKeyPath:@"contentSize" context:sf_observe_context];
    [scrollView removeObserver:self forKeyPath:@"contentInset" context:sf_observe_context];
    if (needadjustedContentInset) {
        [scrollView removeObserver:self forKeyPath:@"adjustedContentInset" context:sf_observe_context];
    }
    
    scrollView.bo_dragScrollView = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (![NSThread isMainThread]) {
#if DEBUG
        @throw [NSException exceptionWithName:@"Main Thread Checker"
                                       reason:@"Main Thread Checker: UI API called on a background thread: setAttachDisplayHAr:"
                                     userInfo:nil];
#else
        //线上的子线程调用保护
        return;
#endif
    }
    
    if (0 == memcmp(context, sf_observe_context, strlen(sf_observe_context))) {
        if (object == _currentScrollView) {
            if ([keyPath isEqualToString:@"contentSize"] &&
                CGSizeEqualToSize(_currentScrollView.contentSize, _lastInnerSCSize)) {
                //有web频繁刷新contentSize但数值没变的情况，kvo依然会发送，过滤一下防止无意义重复
                return;
            }
            //检测到其状态变化，重新加载
            BOOL osychange =\
            !sf_uifloat_equal(_lastSetInnerOSy.y, _currentScrollView.contentOffset.y);
            [self __setupCurrentScrollView:_currentScrollView type:1];
            
            if (!self.bods_isTracking &&
                self.bods_isDecelerating &&
                osychange) {
                //如果重置时发现业务方修改了内部的offset
                [self __setupCurrentScrollView:nil type:1];
                [self setContentOffset:self.contentOffset animated:NO];
            }
        }
    }
    //    return [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)willMoveToWindow:(nullable UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (!newWindow && _currentScrollView) {
        //离开window时，与currentScrollVIew断开连接，释放监听。
        [self __setupCurrentScrollView:nil];
    }
    
}

#pragma mark - API

- (void)setCaAnimationSpeed:(CGFloat)caAnimationSpeed {
    _caAnimationSpeed = MAX(100, MIN(100000, (NSInteger)caAnimationSpeed));
}

- (void)setEmbedView:(UIView *)embedView {
    if (_embedView) {
        if (_currentScrollView) {
            [self __setupCurrentScrollView:nil];
        }
        [_embedView removeFromSuperview];
        self.currDisplayH = 0;
    }
    
    if (self.bods_isDecelerating) {
        //惯性时，终止惯性
        [self setContentOffset:self.contentOffset animated:NO];
    }
    
    _embedView = embedView;
    [self addSubview:embedView];
    _hasLayoutEmbedView = NO;
    //某些系统在addSubview不会自动setNeedsLayout，这里手动设置确保一下
    [self setNeedsLayout];
}

- (UIScrollView *)currentScrollView {
    if (!_currentScrollView.window) {
        [self __setupCurrentScrollView:nil];
    }
    return _currentScrollView;
}

@synthesize currDisplayH = _currDisplayH;
- (CGFloat)currDisplayH {
    return _currDisplayH;
}

- (void)setCurrDisplayH:(CGFloat)currDisplayH {
    
    if (!sf_uifloat_equal(_currDisplayH, currDisplayH)) {
        _currDisplayH = currDisplayH;
        
        //有手势拖拽的起点，表示实在拖拽过程中，标记高度发生变化
        if (nil != _dragBeganDH
            && !_dragDHHasChange) {
            _dragDHHasChange = YES;
        }
        
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:displayHDidChange:)]) {
            [self.dragScrollDelegate dragScrollView:self displayHDidChange:_currDisplayH];
        }
    }
}

- (BOOL)animationSetting {
    return _isScrollAnimating;
}

- (NSNumber *)willLayoutToDisplayH {
    return _needsDisplayH;
}

- (CGFloat)scrollToDisplayH:(CGFloat)displayH animated:(BOOL)animated {
    return [self scrollToDisplayH:displayH animated:animated completion:nil];
}

- (NSValue *)__checkInnerOSForDH:(CGFloat)dh {
    //根据要改的displayH，修改内部scrollview的offset
    if (_innerSVAttInfCount > 0) {
        CGPoint offset = _currentScrollView.contentOffset;
        NSNumber *innershouldosy = nil;
        CGFloat onepxiel = sf_getOnePxiel();
        for (NSInteger infoidx = 0; infoidx < _innerSVAttInfCount; infoidx++) {
            BODragScrollAttachInfo innerscinfo = _innerSVAttInfAr[infoidx];
            if (dh < innerscinfo.displayH - sf_getOnePxiel()) {
                //在最底部
                if (!sf_uifloat_equal(offset.y, innerscinfo.innerOffsetA)) {
                    innershouldosy = @(innerscinfo.innerOffsetA);
                }
                break;
            } else if (dh <= innerscinfo.displayH + onepxiel) {
                
                if (offset.y < innerscinfo.innerOffsetA) {
                    innershouldosy = @(innerscinfo.innerOffsetA);
                } else if (offset.y > innerscinfo.innerOffsetB) {
                    innershouldosy = @(innerscinfo.innerOffsetB);
                }
                
                break;
            } else if (infoidx == _innerSVAttInfCount - 1) {
                if (!sf_uifloat_equal(offset.y, innerscinfo.innerOffsetB)) {
                    innershouldosy = @(innerscinfo.innerOffsetB);
                }
            } else {
                continue;
            }
        }
        
        if (nil != innershouldosy) {
            return [NSValue valueWithCGPoint:CGPointMake(offset.x, innershouldosy.floatValue)];
        }
    }
    
    return nil;
}

- (CGFloat)scrollToDisplayH:(CGFloat)displayH
                   animated:(BOOL)animated
                 completion:(void (^ __nullable)(void))completion {
    return [self scrollToDisplayH:displayH
                         animated:animated
                          subInfo:nil
                       completion:completion];
}

- (CGFloat)scrollToDisplayH:(CGFloat)displayH
                   animated:(BOOL)animated
                    subInfo:(NSDictionary *)subInfo
                 completion:(void (^ __nullable)(void))completion {
    if (_currentScrollView) {
        NSValue *offsetval = [self __checkInnerOSForDH:displayH];
        
        if (offsetval) {
//            UIScrollView *thescv = _currentScrollView;
            [self __setupCurrentScrollView:nil];
            //这里在清空时，将内部捕获的scrollView强制，这个逻辑有点奇怪没看懂，去掉吧先，会导致内部scrollview位置不正确
//            [thescv setContentOffset:offsetval.CGPointValue animated:animated];
        } else {
            [self __setupCurrentScrollView:nil];
        }
    }
    
    //清空待执行动画
    _needsAnimatedToH = nil;
    
    CGFloat validdisplayH = 0;
    
    if (_embedView) {
        NSString *reason = [NSString stringWithFormat:@"outset%@", animated ? @"-ani" : @""];
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:willTargetToH:reason:)]) {
            [self.dragScrollDelegate dragScrollView:self
                                      willTargetToH:displayH
                                             reason:reason];
        }
        
        validdisplayH = displayH;
        if (!_hasLayoutEmbedView) {
            if (animated) {
                //添加待播动画
                _needsAnimatedToH = @(displayH);
            } else {
                //还没有进行首次布局，赋值标记位，到开始布局的时候应用该高度
                _needsDisplayH = @(displayH);
            }
            
        } else {
            CGPoint os = self.contentOffset;
            CGFloat sfh = CGRectGetHeight(self.bounds);
            os.y = displayH - sfh;
            
            CGFloat minosy = -self.contentInset.top;
            CGFloat maxosy = MAX(self.contentSize.height + self.contentInset.bottom - CGRectGetHeight(self.bounds),
                                 -self.contentInset.top);
            //如果滑动改的位置超过最大/最小值，且设置了不允许bounces，那么并不能滑动指定位置。这里做修正
            if (os.y < minosy && !self.allowBouncesCardTop) {
                os.y = minosy;
            } else if (os.y > maxosy && !self.allowBouncesCardBottom) {
                os.y = maxosy;
            }
            validdisplayH = os.y + sfh;
            
            void (^doblock)(void) = ^{
                if (animated) {
                    BOOL forceCAAnimation = NO;
                    if (subInfo) {
                        NSNumber *forceCAAnimationnum = [subInfo objectForKey:@"forceCAAnimation"];
                        if (nil != forceCAAnimationnum) {
                            forceCAAnimation = forceCAAnimationnum.boolValue;
                        }
                    }
                    
                    BODragScrollDecelerateStyle anisel = self.defaultDecelerateStyle;
                    if (forceCAAnimation) {
                        anisel = BODragScrollDecelerateStyleCAAnimation;
                    } else {
                        if (self.dragScrollDelegate && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollViewDecelerate:fromH:toH:reason:)]) {
                            anisel = [self.dragScrollDelegate dragScrollViewDecelerate:self
                                                                                 fromH:self.currDisplayH
                                                                                   toH:displayH
                                                                                reason:reason];
                        }
                        if (BODragScrollDecelerateStyleDefault == anisel) {
                            anisel = self.defaultDecelerateStyle;
                        }
                    }
                    
                    if (BODragScrollDecelerateStyleNature == anisel) {
                        //先清空旧的
                        if (self->_waitMayAnimationScroll) {
                            self->_waitMayAnimationScroll = NO;
                            if (self->_animationScrollDidEndBlock) {
                                self->_animationScrollDidEndBlock();
                                self->_animationScrollDidEndBlock = nil;
                            }
                        }
                        if (!CGPointEqualToPoint(self.contentOffset, os)) {
                            //需要变化，执行切添加回调
                            [self setContentOffset:os animated:YES];
                            
                            self->_waitMayAnimationScroll = YES;
                            self->_animationScrollDidEndBlock = ^{
                                if (completion) {
                                    completion();
                                }
                            };
                        } else {
                            //不需要变化，直接回调
                            if (completion) {
                                completion();
                            }
                        }
                        
                    } else {
                        CGFloat vel = 0;
                        NSNumber *velnum = [subInfo objectForKey:@"vel"];
                        if (nil != velnum) {
                            vel = velnum.boolValue;
                        }
                        [self __liteAnimateToOffset:os vel:vel completion:^(BOOL isFinish) {
                            if (completion) {
                                completion();
                            }
                            
                            if (self.dragScrollDelegate &&
                                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
                                [self.dragScrollDelegate dragScrollView:self
                                                           didTargetToH:self.currDisplayH
                                                                 reason:@"outset-ani"];
                            }
                        }];
                    }
                } else {
                    [self setContentOffset:os animated:NO];
                    if (completion) {
                        completion();
                    }
                    
                    if (self.dragScrollDelegate &&
                        [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
                        [self.dragScrollDelegate dragScrollView:self
                                                   didTargetToH:self.currDisplayH
                                                         reason:@"outset"];
                    }
                }
            };
            
            if (self.layer.presentationLayer && _embedView.layer.presentationLayer) {
                doblock();
            } else {
                //还没有渲染到屏幕上，待渲染完成后再滑动
                [[NSOperationQueue mainQueue] addOperationWithBlock:doblock];
            }
        }
    }
    
    return validdisplayH;
}

- (void)setAttachDisplayHAr:(NSArray<NSNumber *> *)attachDisplayHAr {
    if (![NSThread isMainThread]) {
#if DEBUG
        @throw [NSException exceptionWithName:@"Main Thread Checker"
                                       reason:@"Main Thread Checker: UI API called on a background thread: setAttachDisplayHAr:"
                                     userInfo:nil];
#else
        //线上的子线程调用保护
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setAttachDisplayHAr:attachDisplayHAr];
        });
        return;
#endif
    }
    
    //排序
    _attachDisplayHAr =\
    [attachDisplayHAr sortedArrayUsingComparator:^NSComparisonResult(NSNumber *  _Nonnull obj1, NSNumber *  _Nonnull obj2) {
        return obj1.floatValue - obj2.floatValue;
    }];
    
    //attachDisplayHAr改变后，可展示的最小、最大高度可能会变化，contentinse有可能需要变化
    [self __checkContentInset:nil];
    
    [self forceReloadCurrInnerScrollView];
}

- (void)setPrefDragCardWhenExpand:(BOOL)prefDragCardWhenExpand {
    if (![NSThread isMainThread]) {
#if DEBUG
        @throw [NSException exceptionWithName:@"Main Thread Checker"
                                       reason:@"Main Thread Checker: UI API called on a background thread: setPrefDragCardWhenExpand:"
                                     userInfo:nil];
#else
        //线上的子线程调用保护
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setPrefDragCardWhenExpand:prefDragCardWhenExpand];
        });
        return;
#endif
    }
    
    _prefDragCardWhenExpand = prefDragCardWhenExpand;
    
    [self forceReloadCurrInnerScrollView];
}

- (void)setPrefDragInnerScrollDisplayH:(NSNumber *)prefDragInnerScrollDisplayH {
    if (![NSThread isMainThread]) {
#if DEBUG
        @throw [NSException exceptionWithName:@"Main Thread Checker"
                                       reason:@"Main Thread Checker: UI API called on a background thread: setPrefDragInnerScrollDisplayH:"
                                     userInfo:nil];
#else
        //线上的子线程调用保护
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setPrefDragInnerScrollDisplayH:prefDragInnerScrollDisplayH];
        });
        return;
#endif
    }
    
    _prefDragInnerScrollDisplayH = prefDragInnerScrollDisplayH;
    
    [self forceReloadCurrInnerScrollView];
}

- (void)setMinDisplayH:(NSNumber *)minDisplayH {
    _minDisplayH = minDisplayH;
    //minDisplayH改变后，可展示的最小、最大高度可能会变化，contentinse有可能需要变化
    [self __checkContentInset:nil];
}

- (void)__checkContentInset:(nullable NSArray<NSNumber *> *)attachAr {
    //如果未layout，layout时在layoutSubviews方法里会统一处理contentinset，不需要提前处理
    if (self.embedView && _hasLayoutEmbedView) {
        if (!attachAr) {
            attachAr = self.attachDisplayHAr;
        }
        
        //已经layout的情况下，手动检查和修改状态
        UIEdgeInsets inset = UIEdgeInsetsZero;
        CGFloat selfh = CGRectGetHeight(self.bounds);
        CGFloat mindh = (attachAr.count > 0 ?
                         attachAr.firstObject.floatValue
                         :
                         ((nil != self.minDisplayH) ? self.minDisplayH.floatValue : 66));
        inset.top = selfh - mindh;
        
        if (attachAr.count > 0 && self.embedView) {
            CGFloat maxdh = attachAr.lastObject.floatValue;
            if (maxdh > mindh) {
                inset.bottom = MAX(attachAr.lastObject.floatValue - CGRectGetHeight(self.bounds), 0);
            }
        }
        
        [self innerSetting:^{
            CGPoint oos = self.contentOffset;
            //setContentInset时系统会自己执行checkcontentOffset行为修改了offset，
            self.bo_contentInset = inset;
            //恢复原先offset
            self.bo_contentOffset = oos;
        }];
    }
}

- (void)forceReloadCurrInnerScrollView {
#if DEBUG
    if (![NSThread isMainThread]) {
        @throw [NSException exceptionWithName:@"Main Thread Checker"
                                       reason:@"Main Thread Checker: UI API called on a background thread: forceReloadCurrInnerScrollView"
                                     userInfo:nil];
    }
#endif
    
    //当前已经捕获了内部滑动视图，且初始化过滑动位置，刷新加载
    if (_currentScrollView && _innerSVAttInfCount > 0) {
        [self __setupCurrentScrollView:_currentScrollView];
    }
}

- (void)setInnerScrollViewFirst:(BOOL)innerScrollViewFirst {
    _innerScrollViewFirst = innerScrollViewFirst;
}

#pragma mark - scrollView delegate

//辅助方法，执行动画
- (void)__liteAnimateToOffset:(CGPoint)offset
                          vel:(CGFloat)vel
                   completion:(void (^)(BOOL isFinish))completion {
    CGFloat speed = self.caAnimationSpeed;
    speed = MAX(MIN(100000.f, speed), 100);
    CGFloat based = self.caAnimationBaseDur;
    based = MAX(0, based);
    CGFloat maxd = self.caAnimationMaxDur;
    maxd = MAX(based, maxd);
    
    CGFloat dur = based + fabs(self.contentOffset.y - offset.y) / speed;
    dur = MIN(maxd, dur);
    
    CGFloat damping;
    if (self.caAnimationUseSpring) {
        damping = (vel < 2.2 ? 1 : (vel < 4.4 ? 0.8 : 0.6));
    } else {
        damping = 1;
    }
    
    [UIView animateWithDuration:dur
                          delay:0
         usingSpringWithDamping:damping
          initialSpringVelocity:0
                        options:(UIViewAnimationOptionBeginFromCurrentState
                                 | UIViewAnimationOptionAllowAnimatedContent
                                 | UIViewAnimationOptionAllowUserInteraction
                                 | UIViewAnimationOptionLayoutSubviews)
                     animations:^{
        self.isScrollAnimating = YES;
        self.bo_contentOffset = offset;
    } completion:^(BOOL finished) {
        self.isScrollAnimating = NO;
        if (completion) {
            completion(finished);
        }
    }];
    
    if (self.delayCallDisplayHChangeWhenAnimation) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            CGFloat newdh = CGRectGetHeight(self.bounds) - (CGRectGetMinY(self.embedView.frame) - self.contentOffset.y);
            if (self.needsAnimationWhenDelayCall) {
                [UIView animateWithDuration:dur
                                      delay:0
                     usingSpringWithDamping:damping
                      initialSpringVelocity:0
                                    options:(UIViewAnimationOptionBeginFromCurrentState
                                             | UIViewAnimationOptionAllowAnimatedContent
                                             | UIViewAnimationOptionAllowUserInteraction
                                             | UIViewAnimationOptionLayoutSubviews)
                                 animations:^{
                    self.currDisplayH = newdh;
                } completion:^(BOOL finished) {
                    
                }];
            } else {
                self.currDisplayH = newdh;
            }
        }];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (self.innerSetting) {
        return;
    }
    BOOL isinnersc = NO;
    CGFloat innertotalsc = _totalScrollInnerOSy;
    BOOL triggerinner = NO;
    //暂时不用这个属性，后续有需求可能会用
    __unused BOOL isbounces = NO;
    if (_innerSVAttInfCount > 0) {
        CGFloat innershouldosy = _currentScrollView.contentOffset.y;
        
        CGFloat innerminosy = CGFLOAT_MAX;
        CGFloat innermaxosy = CGFLOAT_MIN;
        for (NSInteger iidx = 0; iidx < _innerSVAttInfCount; iidx++) {
            BODragScrollAttachInfo iinfo = _innerSVAttInfAr[iidx];
            UIScrollView *theinfosv = [self __obtainScrollViewWithIdx:iinfo.scrollViewIdx];
            if (theinfosv == _currentScrollView) {
                innerminosy = MIN(innerminosy, iinfo.innerOffsetA);
                innermaxosy = MAX(innermaxosy, iinfo.innerOffsetB);
            }
        }
        CGFloat minosy = -self.contentInset.top;
        CGFloat maxosy = MAX(self.contentSize.height + self.contentInset.bottom - CGRectGetHeight(self.bounds),
                             -self.contentInset.top);
        
        CGRect embedf = _embedView.frame;
        CGFloat offsety = self.contentOffset.y;
        if (offsety < minosy) {
            isbounces = YES;
            //头部bounces的情况
            CGFloat topext = minosy - offsety;
            
            if (!self.forceBouncesInnerTop
                && (self.allowBouncesCardTop &&
                    (self.prefBouncesCardTop || !_currentScrollView.bounces))) {
                innershouldosy = innerminosy;
                embedf.origin.y = 0;
            } else {
                if (_currentScrollView.bounces) {
                    innershouldosy = innerminosy - topext;
                    embedf.origin.y = -topext;
                    
                    isinnersc = YES;
                } else {
                    //内部不支持bounces
                    CGPoint co = self.contentOffset;
                    co.y = minosy;
                    embedf.origin.y = 0;
                    innershouldosy = innerminosy;
                    [self innerSetting:^{
                        self.bo_contentOffset = co;
                    }];
                    isinnersc = NO;
                }
            }
        } else if (offsety < _minScrollInnerOSy) {
            //正常滑动，还没有进入内部滑动范围
            innershouldosy = innerminosy;
            embedf.origin.y = 0;
            
        } else if (offsety <= _maxScrollInnerOSy) {
            //进入了有可能内部滑动的范围
            CGFloat cursclength = 0;
            BOOL findtheinfo = NO;
            for (NSInteger infoidx = 0; infoidx < _innerSVAttInfCount; infoidx++) {
                BODragScrollAttachInfo innerscinfo = _innerSVAttInfAr[infoidx];
                UIScrollView *theinfosv = [self __obtainScrollViewWithIdx:innerscinfo.scrollViewIdx];
                if (offsety + sf_getOnePxiel() >= innerscinfo.dragSVOffsetY) {
                    CGFloat infomaxsc = innerscinfo.innerOffsetB - innerscinfo.innerOffsetA;
                    if (infoidx + 1 < _innerSVAttInfCount) {
                        //有下一个
                        BODragScrollAttachInfo nextinfo = _innerSVAttInfAr[infoidx + 1];
                        if (offsety < nextinfo.dragSVOffsetY) {
                            //使用当前
                        } else {
                            if (theinfosv == _currentScrollView) {
                                innershouldosy = innerscinfo.innerOffsetB;
                            } else {
                                CGPoint theos = theinfosv.contentOffset;
                                theos.y = innerscinfo.innerOffsetB;
                                theinfosv.bo_contentOffset = theos;
                            }
                            cursclength += infomaxsc;
                            continue;
                        }
                    } else {
                        //没下一个
                        //使用当前
                    }
                    
                    CGFloat exty = offsety - innerscinfo.dragSVOffsetY;
                    if (exty > infomaxsc) {
                        //超过了
                        cursclength += infomaxsc;
                        if (theinfosv == _currentScrollView) {
                            innershouldosy = innerscinfo.innerOffsetB;
                        } else {
                            CGPoint theos = theinfosv.contentOffset;
                            theos.y = innerscinfo.innerOffsetB;
                            theinfosv.bo_contentOffset = theos;
                        }
                        isinnersc = NO;
                    } else {
                        //在该滑动内部的区间
                        cursclength += exty;
                        if (theinfosv == _currentScrollView) {
                            innershouldosy = innerscinfo.innerOffsetA + exty;
                        } else {
                            CGPoint theos = theinfosv.contentOffset;
                            theos.y = innerscinfo.innerOffsetA + exty;
                            theinfosv.bo_contentOffset = theos;
                        }
                        //exty是0的话，标识已经到外部了
                        isinnersc = (exty > 0);
                    }
                    embedf.origin.y = cursclength;
                    findtheinfo = YES;
                    break;
                }
            }
            
            if (findtheinfo) {
                triggerinner = isinnersc;
            } else {
                innershouldosy = innerminosy;
                embedf.origin.y = 0;
                isinnersc = NO;
            }
            
        } else if (offsety <= maxosy) {
            //正常滑动，不在内部滑动范围
            innershouldosy = innermaxosy;
            embedf.origin.y = innertotalsc;
            
        } else {
            isbounces = YES;
            
            //底部bounces情况
            CGFloat bottomext = offsety - maxosy;
            
            //means: offsety > maxosy
            if (self.allowBouncesCardBottom &&
                (self.prefBouncesCardBottom
                 || !_currentScrollView.bounces)) {
                //bounces外部
                embedf.origin.y = innertotalsc;
                innershouldosy = innermaxosy;
            } else {
                //bounces内部
                if (_currentScrollView.bounces) {
                    embedf.origin.y = innertotalsc + bottomext;
                    innershouldosy = innermaxosy + bottomext;
                    
                    isinnersc = YES;
                } else {
                    //内部不支持bounces
                    CGPoint co = self.contentOffset;
                    co.y = maxosy;
                    embedf.origin.y = innertotalsc;
                    innershouldosy = innermaxosy;
                    isinnersc = NO;
                    
                    [self innerSetting:^{
                        self.bo_contentOffset = co;
                    }];
                }
            }
        }
        
        if ([self tryReloadWhenScrollForMissAttach:triggerinner]) {
            return;
        }
        
        CGPoint inneroffset = _currentScrollView.contentOffset;
        inneroffset.y = innershouldosy;
        [self innerSetting:^{
            //要先设EmbedViewFrame再setCurrentSVContentOffset，否则setCurrentSVContentOffset可能引起系统的重新布局矫正CurrentSV的ContentOffset
            [self setEmbedViewFrame:embedf];
            if (0 == self->_missAttachAndNeedsReload) {
                [self setCurrentSVContentOffset:inneroffset];
            }
        }];
    } else {
        
        if ([self tryReloadWhenScrollForMissAttach:triggerinner]) {
            return;
        }
        
        CGFloat coy = self.contentOffset.y;
        CGFloat minosy = -self.contentInset.top;
        CGFloat maxosy =\
        MAX(minosy, self.contentSize.height + self.contentInset.bottom - CGRectGetHeight(self.bounds));
        CGRect embedf = _embedView.frame;
        if (coy > maxosy && !self.allowBouncesCardBottom) {
            isbounces = YES;
            embedf.origin.y = coy - maxosy;
            [self innerSetting:^{
                [self setEmbedViewFrame:embedf];
            }];
        } else if (coy < minosy && !self.allowBouncesCardTop) {
            isbounces = YES;
            embedf.origin.y = coy - minosy;
            [self innerSetting:^{
                [self setEmbedViewFrame:embedf];
            }];
        } else if (embedf.origin.y != 0) {
            embedf.origin.y = 0;
            [self innerSetting:^{
                [self setEmbedViewFrame:embedf];
            }];
        }
    }
    
    _lastScrollIsInner = isinnersc;
    
    //寻找scrollView的Indicator并展示 有点track  容后再议~
    if (isinnersc && self.bods_isTracking &&
        _currentScrollView && _currentScrollView.showsVerticalScrollIndicator &&
        self.autoShowInnerIndictor) {
        for (UIView *subv in _currentScrollView.subviews) {
            
            if ([subv isKindOfClass:[UIImageView class]] &&
                sf_uifloat_equal(subv.frame.size.width, 2.5)) {
                subv.alpha = 1;
                subv.tag = sf_indictor_tag;
            }
        }
    }
    
    CGFloat newdh = CGRectGetHeight(self.bounds) - (CGRectGetMinY(_embedView.frame) - self.contentOffset.y);
    
    //滑动外部时使用DecelerationRateFast
    if (scrollView.bods_isTracking) {
        if (isinnersc && _currentScrollView) {
            super.decelerationRate = _currentScrollView.decelerationRate;
        } else {
            super.decelerationRate = _curDecelerationRate;
        }
    }
    
    //更新面板展示高度
    if (!self.isScrollAnimating || !self.delayCallDisplayHChangeWhenAnimation) {
        self.currDisplayH = newdh;
    }
    
    //通知滑动回调
    if (self.dragScrollDelegate &&
        [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didScroll:isInner:)]) {
        [self.dragScrollDelegate dragScrollView:self
                                      didScroll:newdh
                                        isInner:isinnersc];
    }
}

- (BOOL)tryReloadWhenScrollForMissAttach:(BOOL)currTriggerInner {
    if (0 != _missAttachAndNeedsReload
        && _currentScrollView) {
        if (currTriggerInner) {
            //到达内部点，重置位置
            _missAttachAndNeedsReload = 0;
            [self __setupCurrentScrollView:_currentScrollView];
            return YES;
        } else if (nil != _scrollBeganLoc) {
            CGFloat vely = [self.panGestureRecognizer velocityInView:self.window].y;
            /*
             非内部点，根据手指方向，决定是继续滑动还是重置内部
             点在上面，但向下滑了，此时reset点
             点在下面，但向上滑了，此时reset点
             */
            if ((_missAttachAndNeedsReload > 0
                 && vely > 0)
                || (_missAttachAndNeedsReload < 0
                    && vely < 0)) {
                _missAttachAndNeedsReload = 0;
                _forceResetWhenScroll = YES;
                [self __setupCurrentScrollView:_currentScrollView];
                _forceResetWhenScroll = NO;
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)tryReloadWhenPanBegan {
    if (nil != _scrollBeganLoc) {
        CGFloat vely = [self.panGestureRecognizer velocityInView:self.window].y;
        /*
         非内部点，根据手指方向，决定是继续滑动还是重置内部
         点在上面，但向下滑了，此时reset点
         点在下面，但向上滑了，此时reset点
         */
        if ((_missAttachAndNeedsReload > 0
             && vely > 0)
            || (_missAttachAndNeedsReload < 0
                && vely < 0)) {
            _missAttachAndNeedsReload = 0;
            _forceResetWhenScroll = YES;
            [self __setupCurrentScrollView:_currentScrollView];
            _forceResetWhenScroll = NO;
            return YES;
        }
    }
    return NO;
}

- (BODragScrollAttachInfo *)__obtainCurrentAttachInfo:(NSInteger *)count {
    NSInteger maxcount = _innerSVAttInfCount + self.attachDisplayHAr.count;
    BODragScrollAttachInfo *atinfoar =\
    (BODragScrollAttachInfo *)malloc(maxcount * sizeof(BODragScrollAttachInfo));
    NSInteger curcount = 0;
    CGFloat totalinnersc = 0;
    CGFloat sfh = CGRectGetHeight(self.bounds);
    for (NSInteger idxa = 0, idxb = 0;
         idxa < self.attachDisplayHAr.count || idxb < _innerSVAttInfCount;
         ) {
        CGFloat adh = 0;
        BODragScrollAttachInfo binfo;
        NSNumber *aYESbNO = nil;
        if (idxa < self.attachDisplayHAr.count) {
            adh = self.attachDisplayHAr[idxa].floatValue;
            aYESbNO = @(YES);
        }
        
        if (idxb < _innerSVAttInfCount) {
            binfo = _innerSVAttInfAr[idxb];
            if (nil != aYESbNO && aYESbNO.boolValue) {
                if (binfo.displayH < (adh - sf_getOnePxiel())) {
                    aYESbNO = @(NO);
                    idxb++;
                } else if (binfo.displayH > (adh + sf_getOnePxiel())) {
                    idxa++;
                } else {
                    //两个高度相等，使用b的信息，因为要把里面滑动内部的信息带上
                    aYESbNO = @(NO);
                    idxa++;
                    idxb++;
                }
            } else {
                aYESbNO = @(NO);
                idxb++;
            }
        } else {
            idxa++;
        }
        
        if (nil != aYESbNO) {
            BODragScrollAttachInfo newinfo;
            if (aYESbNO.boolValue) {
                CGFloat dosy = totalinnersc + adh - sfh;
                newinfo =\
                (BODragScrollAttachInfo){0, adh, dosy, NO, 0, 0, dosy};
            } else {
                //                CGFloat dosy = totalinnersc + binfo.displayH - sfh;
                //                atinfoar[curcount] =\
                //                (BODragScrollAttachInfo){binfo.displayH, dosy,
                //                    YES, binfo.innerOffsetA, binfo.innerOffsetB,
                //                    dosy + (binfo.innerOffsetB - binfo.innerOffsetA)};
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wconditional-uninitialized"
                newinfo = binfo;
#pragma clang diagnostic pop
            }
            totalinnersc += newinfo.innerOffsetB - newinfo.innerOffsetA;
            atinfoar[curcount] = newinfo;
            curcount++;
        } else {
            //不应发生
            break;
        }
    }
    
    if (count) {
        *count = curcount;
    }
    
    if (0 == curcount) {
        free(atinfoar);
        atinfoar = NULL;
    }
    return atinfoar;
}

- (NSInteger)__findIdxInAttInfoAr:(BODragScrollAttachInfo *)attinfoAr
                            count:(NSInteger)count
                      dragOffsetY:(CGFloat)offsetY
                         accuracy:(CGFloat)accuracy
                              loc:(NSInteger *)loc {
    for (NSInteger idx = 0; idx < count; idx++) {
        BODragScrollAttachInfo info = attinfoAr[idx];
        if (offsetY < info.dragSVOffsetY - accuracy) {
            if (idx - 1 >= 0) {
                BODragScrollAttachInfo lastinfo = attinfoAr[idx - 1];
                if (offsetY - lastinfo.dragSVOffsetY2 < info.dragSVOffsetY - offsetY) {
                    if (loc) {
                        *loc = 1;
                    }
                    return idx - 1;
                } else {
                    if (loc) {
                        *loc = -1;
                    }
                    return idx;
                }
            } else {
                if (loc) {
                    *loc = -1;
                }
                return idx;
            }
            
        } else if (offsetY <= info.dragSVOffsetY2 + accuracy) {
            if (loc) {
                *loc = 0;
            }
            return idx;
        } else if (count - 1 == idx) {
            if (loc) {
                *loc = 1;
            }
            return idx;
        }
    }
    
    return 0;
}

/*
 只有内部在使用，暂不必用enum
 return:
 00: 无特殊滑动逻辑
 11: 内部滑向内部
 12: 内部滑向外部
 21: 外部滑向内部
 22: 外部滑向外部
 32: bounces状态弹回置顶、置底
 */
- (NSInteger)__scrollViewWillEndDragging:(UIScrollView *)scrollView
                            withVelocity:(CGPoint)velocity
                     targetContentOffset:(inout CGPoint *)targetContentOffset
                              attachInfo:(BODragScrollAttachInfo *)attachInfo {
    if (self.attachDisplayHAr.count <= 0) {
        return 0;
    }
    
    NSInteger atinfocount = 0;
    BODragScrollAttachInfo *atinfoar = [self __obtainCurrentAttachInfo:&atinfocount];
    
    if (atinfocount <= 0) {
        return 0;
    }
    
    NSInteger scrolltype = 0;
    CGFloat onepxiel = sf_getOnePxiel();
    
    CGPoint targetos = *targetContentOffset;
    CGFloat toy = targetos.y;
    CGFloat curosy = self.contentOffset.y;
    
    BODragScrollAttachInfo tarinfo;
    NSInteger taridx = 0;
    NSInteger tarloc = -1;
    
    BODragScrollAttachInfo curinfo;
    NSInteger curidx = 0;
    NSInteger curloc = -1;
    
    curidx = [self __findIdxInAttInfoAr:atinfoar count:atinfocount dragOffsetY:curosy accuracy:onepxiel loc:&curloc];
    curinfo = atinfoar[curidx];
    taridx = [self __findIdxInAttInfoAr:atinfoar count:atinfocount dragOffsetY:toy accuracy:onepxiel loc:&tarloc];
    tarinfo = atinfoar[taridx];
    
    BOOL curinsc = (0 == curloc && curinfo.dragInner);
    BOOL tarinsc = (0 == tarloc && tarinfo.dragInner);
    
    if (!tarinsc) {
        NSNumber *tardh = nil;
        if (toy < tarinfo.dragSVOffsetY) {
            tardh = @(tarinfo.displayH - tarinfo.dragSVOffsetY + toy);
        } else if (toy > tarinfo.dragSVOffsetY2) {
            tardh = @(tarinfo.displayH + toy - tarinfo.dragSVOffsetY);
        }
        
        if (nil != tardh) {
            if (self.dragScrollDelegate &&
                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:shouldMisAttachForH:)]) {
                if ([self.dragScrollDelegate dragScrollView:self shouldMisAttachForH:tardh.floatValue]) {
                    free(atinfoar);
                    return 0;
                }
            } else if (self.misAttachRangeAr.count > 0) {
                CGFloat tardhf = tardh.floatValue;
                __block BOOL shouldMis = NO;
                [self.misAttachRangeAr enumerateObjectsUsingBlock:^(NSValue * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    CGPoint rgpt = obj.CGPointValue;
                    if (tardhf > (rgpt.x - onepxiel) &&
                        tardhf < (rgpt.y + onepxiel)) {
                        shouldMis = YES;
                        *stop = YES;
                    }
                }];
                
                if (shouldMis) {
                    free(atinfoar);
                    return 0;
                }
            }
        }
    }
    
    CGFloat fvel = fabs(velocity.y);
    if (curinsc) {
        if (tarinsc) {
            //内部滑向内部
            scrolltype = 11;
            
            if (curidx != taridx) {
                //跨区间
                if (fvel < 0.2) {
                    taridx = curidx;
                    tarloc = toy > curosy ? 1 : -1;
                    tarinfo = curinfo;
                } else {
                    if (velocity.y > 0) {
                        if (curidx + 1 < atinfocount) {
                            taridx = curidx + 1;
                            tarloc = -1;
                        } else {
                            taridx = curidx;
                            tarloc = 1;
                        }
                    } else {
                        if (curidx - 1 >= 0) {
                            taridx = curidx - 1;
                            tarloc = 1;
                        } else {
                            taridx = curidx;
                            tarloc = -1;
                        }
                    }
                    
                    tarinfo = atinfoar[taridx];
                    scrolltype = 12;
                }
                
                toy = (tarloc < 0 ? tarinfo.dragSVOffsetY : tarinfo.dragSVOffsetY2);
            } else {
                //没有跨区间，正常滑动即可，不介入
            }
        } else {
            scrolltype = 12;
            //内部滑向外部
            
            if (curidx == taridx) {
                //还没滑出当前吸附范围
                if (toy > tarinfo.dragSVOffsetY2) {
                    toy = tarinfo.dragSVOffsetY2;
                } else if (toy < tarinfo.dragSVOffsetY) {
                    toy = tarinfo.dragSVOffsetY;
                }
            } else {
                if (self.disableInnerScrollToOut) {
                    taridx = curidx;
                    tarloc = curloc;
                    tarinfo = curinfo;
                    if (toy > tarinfo.dragSVOffsetY2) {
                        toy = tarinfo.dragSVOffsetY2;
                    } else if (toy < tarinfo.dragSVOffsetY) {
                        toy = tarinfo.dragSVOffsetY;
                    }
                } else {
                    CGFloat minlength = 86; //86是调手感调出来的数字
                    if (velocity.y > 0) {
                        if (fvel > 2.2 &&
                            curosy > curinfo.dragSVOffsetY2 - minlength &&
                            curidx + 1 < atinfocount) {
                            taridx = curidx + 1;
                            tarloc = -1;
                            tarinfo = atinfoar[taridx];
                        } else {
                            taridx = curidx;
                            tarloc = 1;
                            tarinfo = curinfo;
                        }
                    } else {
                        if (fvel > 2.2 &&
                            curosy < curinfo.dragSVOffsetY + minlength &&
                            curidx - 1 >= 0) {
                            taridx = curidx - 1;
                            tarloc = 1;
                            tarinfo = atinfoar[taridx];
                        } else {
                            taridx = curidx;
                            tarloc = -1;
                            tarinfo = curinfo;
                        }
                    }
                    toy = (tarloc < 0 ? tarinfo.dragSVOffsetY : tarinfo.dragSVOffsetY2);
                }
                
            }
        }
    } else {
        if (tarinsc) {
            scrolltype = 21;
            //外部滑向内部
            CGFloat minscdy = 140; //140是调手感调出来的数字
            if (curosy < tarinfo.dragSVOffsetY && toy - tarinfo.dragSVOffsetY < minscdy) {
                //从上向内滑，范围较小，吸附
                toy = tarinfo.dragSVOffsetY;
            } else if (curosy > tarinfo.dragSVOffsetY2 && tarinfo.dragSVOffsetY2 - toy < minscdy) {
                //从下向内滑，范围较小，吸附
                toy = tarinfo.dragSVOffsetY2;
            } else {
                //正常滑动，什么也不做
                
                //                CGFloat k = 4;
                //                //以特定阻尼系数滑动
                //                CGFloat t = -log(stopv/curv) / k;
                //                CGFloat s = curosy - (curv * (exp(-k*t) - 1) / k);
                //                toy = s;
            }
        } else {
            scrolltype = 22;
            //外部滑向外部
            if (fvel < 0.2) {
                taridx = curidx;
                tarloc = curloc;
                tarinfo = curinfo;
            } else {
                if (velocity.y > 0) {
                    //由小到大
                    if (curloc < 0) {
                        CGFloat minlength = 86; //86是调手感调出来的数字
                        if (fvel > 2.2 &&
                            ((curinfo.dragSVOffsetY - curosy) < minlength)) {
                            //惯性较大且靠近终点，希望再往后多跳一格
                            if (curidx + 1 < atinfocount) {
                                taridx = curidx + 1;
                                tarloc = -1;
                            } else {
                                taridx = curidx;
                                tarloc = -1;
                            }
                        } else {
                            taridx = curidx;
                            tarloc = -1;
                        }
                    } else {
                        if (curidx + 1 < atinfocount) {
                            taridx = curidx + 1;
                            tarloc = -1;
                        } else {
                            taridx = curidx;
                            tarloc = 1;
                        }
                    }
                } else {
                    //由大到小
                    if (curloc > 0) {
                        CGFloat minlength = 86;
                        if (fvel > 2.2 &&
                            ((curosy - curinfo.dragSVOffsetY2) < minlength)) {
                            //惯性较大且靠近终点，希望再往后多跳一格
                            if (curidx - 1 >= 0) {
                                taridx = curidx - 1;
                                tarloc = 1;
                            } else {
                                taridx = curidx;
                                tarloc = -1;
                            }
                        } else {
                            taridx = curidx;
                            tarloc = 1;
                        }
                    } else {
                        if (self.shrinkResistance) {
                            CGFloat minlength = 86;
                            if ((curinfo.dragSVOffsetY - curosy) < minlength) {
                                taridx = curidx;
                                tarloc = curloc;
                            } else {
                                if (curidx - 1 >= 0) {
                                    taridx = curidx - 1;
                                    tarloc = 1;
                                } else {
                                    taridx = curidx;
                                    tarloc = -1;
                                }
                            }
                        } else {
                            if (curidx - 1 >= 0) {
                                taridx = curidx - 1;
                                tarloc = 1;
                            } else {
                                taridx = curidx;
                                tarloc = -1;
                            }
                        }
                        
                    }
                }
                
                tarinfo = atinfoar[taridx];
            }
            
            toy = (tarloc < 0 ? tarinfo.dragSVOffsetY : tarinfo.dragSVOffsetY2);
        }
        
        //由bounces状态弹到置顶、置底状态
        if ((curosy < -self.contentInset.top && sf_uifloat_equal(toy, -self.contentInset.top))
            ||
            (curosy >
             MAX(self.contentSize.height + self.contentInset.bottom - CGRectGetHeight(self.bounds),
                 -self.contentInset.top))) {
            scrolltype = 32;
        }
    }
    
    //最终停留位置在内部时，调用内部scrollView的delegate
    if (_currentScrollView &&
        _currentScrollView.delegate &&
        [_currentScrollView.delegate respondsToSelector:@selector(scrollViewWillEndDragging:withVelocity:targetContentOffset:)]) {
        
        //落点在内部，需要保证其在begin和end点之间，若数值表示上面的代码被改坏了
        //            NSAssert(((*targetContentOffset).y > _minScrollInnerOSy && (*targetContentOffset).y < _maxScrollInnerOSy),
        //                     @"数值错误");
        CGFloat innerscl = toy - _minScrollInnerOSy;
        UIEdgeInsets innerinsets = sf_common_contentInset(_currentScrollView);
        CGPoint inostarget = _currentScrollView.contentOffset;
        CGFloat currinnertarget = innerscl - innerinsets.top;
        inostarget.y = currinnertarget;
        [_currentScrollView.delegate scrollViewWillEndDragging:_currentScrollView
                                                  withVelocity:velocity
                                           targetContentOffset:&inostarget];
        //目前暂定：本身落点在内部时，才会受内部targetContentOffset修改的影响，若本身落点不在内部，则不被内部的设置干扰
        if ((11 == scrolltype || 21 == scrolltype) &&
            !sf_uifloat_equal(currinnertarget, inostarget.y)) {
            //数值被修改了，校验合法性
            CGFloat outtargety = inostarget.y  + innerinsets.top + _minScrollInnerOSy;
            NSInteger outtarloc = -1;
            NSInteger outtaridx = [self __findIdxInAttInfoAr:atinfoar
                                                       count:atinfocount
                                                 dragOffsetY:outtargety
                                                    accuracy:onepxiel
                                                         loc:&outtarloc];
            BODragScrollAttachInfo outtarinfo = atinfoar[outtaridx];
            if (outtaridx == taridx) {
                if (outtarloc < 0) {
                    outtarloc = outtarinfo.dragSVOffsetY;
                } else if (outtarloc > 0) {
                    outtarloc = outtarinfo.dragSVOffsetY2;
                }
                
                toy = outtargety;
            }
            
        }
    }
    
    free(atinfoar);
    
    if (attachInfo) {
        *attachInfo = tarinfo;
    }
    
    targetos.y = toy;
    *targetContentOffset = targetos;
    
    return scrolltype;
}

- (BOOL)accessibilityScroll:(UIAccessibilityScrollDirection)direction {
    if (!self.embedView) {
        return NO;
    }
    
    NSNumber *dacontrol = nil;
    if (self.dragScrollDelegate
        && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:accessibilityScroll:)]) {
        dacontrol = [self.dragScrollDelegate dragScrollView:self
                                        accessibilityScroll:direction];
    }
    
    if (nil != dacontrol && dacontrol.boolValue) {
        //业务已接管
        return YES;
    }
    
    if (UIAccessibilityScrollDirectionDown == direction) {
        if (self.attachDisplayHAr.count > 0) {
            NSInteger toidx = bo_findIdxInFloatArrayByValue(self.attachDisplayHAr,
                                                            self.currDisplayH + 1, NO, YES);
            if (toidx < self.attachDisplayHAr.count) {
                CGFloat toh = self.attachDisplayHAr[toidx].floatValue;
                if (toh != self.currDisplayH) {
                    [self scrollToDisplayH:toh animated:YES];
                    return YES;
                }
            }
        } else {
            if (!_currentScrollView) {
                UIEdgeInsets cinset = sf_common_contentInset(self);
                [self setContentOffset:CGPointMake(0, cinset.bottom + self.contentSize.height - self.bounds.size.height)
                              animated:YES];
            }
        }
        
    } else if (UIAccessibilityScrollDirectionUp == direction) {
        if (self.attachDisplayHAr.count > 0) {
            if (self.currDisplayH == self.attachDisplayHAr.lastObject.floatValue) {
                //若代理未显示告知_currentScrollView不处理，对_currentScrollView进行只能判定
                if (nil == dacontrol) {
                    if (!_currentScrollView) {
                        UIView *targetview =\
                        [self hitTest:CGPointMake(CGRectGetMidX(self.bounds),
                                                  CGRectGetMidY(self.bounds))
                            withEvent:nil];
                        [self trySetupCurrentScrollViewWithContentView:targetview];
                    }
                    
                    if (_currentScrollView) {
                        UIEdgeInsets cinset = sf_common_contentInset(_currentScrollView);
                        if (_currentScrollView.contentOffset.y > -cinset.top) {
                            return NO;
                        }
                    }
                }
            }
            
            NSInteger toidx = bo_findIdxInFloatArrayByValue(self.attachDisplayHAr,
                                                            self.currDisplayH - 1, NO, NO);
            if (toidx < self.attachDisplayHAr.count) {
                CGFloat toh = self.attachDisplayHAr[toidx].floatValue;
                if (toh != self.currDisplayH) {
                    [self scrollToDisplayH:toh animated:YES];
                    return YES;
                }
            }
        } else {
            if (!_currentScrollView) {
                UIEdgeInsets cinset = sf_common_contentInset(self);
                [self setContentOffset:CGPointMake(0, -cinset.top)
                              animated:YES];
            }
        }
    }
    
    return NO;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    
    BODragScrollAttachInfo theinfo;
    NSInteger scrolltype =\
    [self __scrollViewWillEndDragging:scrollView
                         withVelocity:velocity
                  targetContentOffset:targetContentOffset
                           attachInfo:&theinfo];
    
    if (self.dragScrollDelegate && [self.dragScrollDelegate respondsToSelector:@selector(scrollViewWillEndDragging:withVelocity:targetContentOffset:)]) {
        [self.dragScrollDelegate scrollViewWillEndDragging:scrollView
                                              withVelocity:velocity
                                       targetContentOffset:targetContentOffset];
    }
    
    CGFloat dragoutdy = (*targetContentOffset).y;
    CGFloat newdh;
    if (_innerSVAttInfCount > 0) {
        if (dragoutdy < theinfo.dragSVOffsetY) {
            newdh = theinfo.displayH - theinfo.dragSVOffsetY + dragoutdy;
        } else if (dragoutdy <= theinfo.dragSVOffsetY2) {
            newdh = theinfo.displayH;
        } else {
            newdh = theinfo.displayH + dragoutdy - theinfo.dragSVOffsetY2;
        }
    } else {
        newdh = CGRectGetHeight(self.bounds) + dragoutdy;
    }
    
    BOOL willdecelerate =\
    (!sf_uifloat_equal((*targetContentOffset).y, self.contentOffset.y));
    
    NSString *reason = [NSString stringWithFormat:@"willEndDragging%@", willdecelerate ? @"-willdecelerate" : @""];
    //整个drag过程中，displayHeight没发生过变化，则不用触发TargetTo
    
    //中间没有变化，且结果也不会变化，不需要发target变化的回调
    BOOL ignoretargetto = !_dragDHHasChange && sf_uifloat_equal(newdh, _dragBeganDH.floatValue);
    //恢复拖拽相关标记位
    _dragBeganDH = nil;
    _dragDHHasChange = NO;
    
    if (!ignoretargetto) {
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:willTargetToH:reason:)]) {
            [self.dragScrollDelegate dragScrollView:self
                                      willTargetToH:newdh
                                             reason:reason];
        }
        
        _waitDidTargetTo = YES;
    }
    
    if (22 == scrolltype && willdecelerate) {
        //外部滑向外部才需要选择动画
        BODragScrollDecelerateStyle anisel = self.defaultDecelerateStyle;
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollViewDecelerate:fromH:toH:reason:)]) {
            anisel = [self.dragScrollDelegate dragScrollViewDecelerate:self
                                                                 fromH:self.currDisplayH
                                                                   toH:newdh
                                                                reason:reason];
        }
        if (BODragScrollDecelerateStyleDefault == anisel) {
            anisel = self.defaultDecelerateStyle;
        }
        
        if (BODragScrollDecelerateStyleCAAnimation == anisel) {
            //先停止惯性，停止过程不需要调WaitDidTargetTo
            _ignoreWaitDidTargetTo = YES;
            [scrollView setContentOffset:scrollView.contentOffset animated:NO];
            _ignoreWaitDidTargetTo = NO;
            
            //使用lite动画
            CGPoint toos = *targetContentOffset;
            CGFloat vely = 0;
            if ((toos.y > self.contentOffset.y) == (velocity.y > 0)) {
                //滑动方向和手势方向相同
                vely = fabs(velocity.y);
            }
            
            BOOL shouldtargetto = _waitDidTargetTo && !_ignoreWaitDidTargetTo;
            _waitDidTargetTo = NO;
            [self __liteAnimateToOffset:toos vel:vely completion:^(BOOL isFinish) {
                if (shouldtargetto) {
                    if (self.dragScrollDelegate &&
                        [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
                        [self.dragScrollDelegate dragScrollView:self
                                                   didTargetToH:self.currDisplayH
                                                         reason:@"didEndDragging-inset-ani"];
                    }
                }
            }];
        }
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (_innerSVAttInfCount > 0 &&
        _currentScrollView.delegate &&
        [_currentScrollView.delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [_currentScrollView.delegate scrollViewDidEndDragging:_currentScrollView willDecelerate:decelerate];
    }
    
    if ([self.dragScrollDelegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) {
        [self.dragScrollDelegate scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    }
    
    if (!_ignoreWaitDidTargetTo
        && !decelerate
        && _waitDidTargetTo) {
        _waitDidTargetTo = NO;
        //会在稍后停止TrackingRunLoopMode
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
            [self.dragScrollDelegate dragScrollView:self
                                       didTargetToH:self.currDisplayH
                                             reason:@"didEndDragging"];
        }
    }
    
    //如果设置过indictor 就闪一下吧
    if (_currentScrollView && self.autoShowInnerIndictor) {
        [self __dismissIndictor:_currentScrollView];
    }
    
    if (!decelerate) {
        if (_waitMayAnimationScroll) {
            __weak typeof(self) ws = self;
            _animationScrollDidEndBlock = ^{
                [ws __setupCurrentScrollView:nil];
            };
        } else {
            [self __setupCurrentScrollView:nil];
        }
    }
    
    if (_theCtrWhenDecInner) {
        CGPoint pt = [self.panGestureRecognizer locationInView:self.window];
        CGRect thert = [_theCtrWhenDecInner convertRect:_theCtrWhenDecInner.bounds
                                                 toView:self.window];
        if (CGRectContainsPoint(thert, pt)) {
            [_theCtrWhenDecInner sendActionsForControlEvents:UIControlEventTouchUpInside];
        } else {
            [_theCtrWhenDecInner sendActionsForControlEvents:UIControlEventTouchUpOutside];
        }
        _theCtrWhenDecInner = nil;
    }
    
    _scrollBeganLoc = nil;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (_innerSVAttInfCount > 0 &&
        _currentScrollView.delegate &&
        [_currentScrollView.delegate respondsToSelector:@selector(scrollViewDidEndDecelerating:)]) {
        [_currentScrollView.delegate scrollViewDidEndDecelerating:_currentScrollView];
    }
    
    if (!_ignoreWaitDidTargetTo
        && _waitDidTargetTo) {
        _waitDidTargetTo = NO;
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
            [self.dragScrollDelegate dragScrollView:self
                                       didTargetToH:self.currDisplayH
                                             reason:@"didEndDragging-endDecelerate"];
        }
    }
    
    if ([self.dragScrollDelegate respondsToSelector:@selector(scrollViewDidEndDecelerating:)]) {
        [self.dragScrollDelegate scrollViewDidEndDecelerating:scrollView];
    }
    
    if (!self.bods_isTracking) {
        if (_waitMayAnimationScroll) {
            __weak typeof(self) ws = self;
            _animationScrollDidEndBlock = ^{
                [ws __setupCurrentScrollView:nil];
            };
        } else {
            [self __setupCurrentScrollView:nil];
        }
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _scrollBeganLoc = @([scrollView.panGestureRecognizer locationInView:scrollView.window]);
    /*
     拖拽起始时的展示高度
     */
    _dragBeganDH = @(_currDisplayH);
    _dragDHHasChange = NO;
    
    if (_needsFixDisplayHWhenTouchEnd) {
        //开始响应手势滑动了，自会在滑动结束后重置位置，不需要_dsTapGes的抬起修正了
        _needsFixDisplayHWhenTouchEnd = NO;
        [_dsTapGes finishRecognizer];
    }
    
    if (_innerSVAttInfCount > 0 &&
        _currentScrollView.delegate &&
        [_currentScrollView.delegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
        [_currentScrollView.delegate scrollViewWillBeginDragging:_currentScrollView];
    }
    
    if ([self.dragScrollDelegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
        [self.dragScrollDelegate scrollViewWillBeginDragging:scrollView];
    }
    
    [self tryReloadWhenPanBegan];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (_waitMayAnimationScroll) {
        _waitMayAnimationScroll = NO;
        if (_animationScrollDidEndBlock) {
            _animationScrollDidEndBlock();
            _animationScrollDidEndBlock = nil;
        }
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
            [self.dragScrollDelegate dragScrollView:self
                                       didTargetToH:self.currDisplayH
                                             reason:@"outset-ani"];
        }
    }
    
    if ([self.dragScrollDelegate respondsToSelector:@selector(scrollViewDidEndScrollingAnimation:)]) {
        [self.dragScrollDelegate scrollViewDidEndScrollingAnimation:scrollView];
    }
    
    _lastAniScrollEndTS = [NSDate date].timeIntervalSince1970;
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
    BOOL should = YES;
    if ([self.dragScrollDelegate respondsToSelector:@selector(scrollViewShouldScrollToTop:)]) {
        should = [self.dragScrollDelegate scrollViewShouldScrollToTop:scrollView];
    }
    
    if (should &&
        self.dragScrollDelegate &&
        [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:willTargetToH:reason:)]) {
        CGFloat newdh =\
        CGRectGetHeight(self.bounds) - (CGRectGetMinY(_embedView.frame) + self.contentInset.top);
        [self.dragScrollDelegate dragScrollView:self
                                  willTargetToH:newdh
                                         reason:@"ScrollToTop"];
    }
    
    return should;
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView {
    if ([self.dragScrollDelegate respondsToSelector:@selector(scrollViewDidScrollToTop:)]) {
        [self.dragScrollDelegate scrollViewDidScrollToTop:scrollView];
    }
    
    if (self.dragScrollDelegate &&
        [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
        [self.dragScrollDelegate dragScrollView:self
                                   didTargetToH:self.currDisplayH
                                         reason:@"ScrollToTop"];
    }
}

#pragma mark - gesture

//不实现该方法，默认NO即可
//当gestureRecognizer遇到otherGestureRecognizer，是否希望将gestureRecognizer失效
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == _dsTapGes) {
        return NO;
    } else if (gestureRecognizer.view == self) {
        if (otherGestureRecognizer.view == _currentScrollView) {
            if (self.innerScrollViewFirst) {
                return YES;
            } else {
                return NO;
            }
        } else {
            //本组件的gestureRecognizer碰到其它View（非当前捕获_currentScrollView）
            if (self.dragScrollDelegate &&
                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:recognizeStrategyForGes:otherGes:)]) {
                NSInteger strategy =\
                [self.dragScrollDelegate dragScrollView:self
                                recognizeStrategyForGes:gestureRecognizer
                                               otherGes:otherGestureRecognizer];
                if (NSNotFound != strategy) {
                    switch (strategy) {
                        case 0:
                            return NO;
                        case -1:
                            return YES;
                        case 1:
                            return NO;
                        case 3:
                            return NO;
                        default:
                            return NO;
                    }
                }
            }
            
            if ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
                NSInteger prioritybeg = [self __priorityBehaviorForInnerSV:(id)otherGestureRecognizer.view];
                switch (prioritybeg) {
                    case -1:
                        return NO;
                    case 0:
                        return NO;
                    case 1:
                        return YES;
                    case 2:
                        return NO;
                    case 3:
                        return NO;
                    default:
                        return NO;
                }
            } else {
                return NO;
            }
        }
    } else {
        return NO;
    }
}

//当gestureRecognizer遇到otherGestureRecognizer，是否希望将otherGestureRecognizer失效
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == _dsTapGes) {
        return NO;
    } else if (gestureRecognizer.view == self) {
        if (otherGestureRecognizer.view == _currentScrollView) {
            if (self.innerScrollViewFirst) {
                return NO;
            } else {
                return YES;
            }
        } else {
            //本组件的gestureRecognizer碰到其它View（非当前捕获_currentScrollView）
            if (self.dragScrollDelegate &&
                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:recognizeStrategyForGes:otherGes:)]) {
                NSInteger strategy =\
                [self.dragScrollDelegate dragScrollView:self
                                recognizeStrategyForGes:gestureRecognizer
                                               otherGes:otherGestureRecognizer];
                if (NSNotFound != strategy) {
                    switch (strategy) {
                        case 0:
                            return NO;
                        case -1:
                            return NO;
                        case 1:
                            return YES;
                        case 3:
                            return NO;
                        default:
                            return NO;
                    }
                }
            }
            
            if (self.bods_isDecelerating &&
                [otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
                //若shouldFailureOtherTapGestureWhenDecelerating=YES则无效其他View的本次tap
                return self.shouldFailureOtherTapGestureWhenDecelerating ? YES : NO;
            } else {
                if ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
                    NSInteger prioritybeg = [self __priorityBehaviorForInnerSV:(id)otherGestureRecognizer.view];
                    switch (prioritybeg) {
                        case -1:
                            return YES;
                        case 0:
                            return NO;
                        case 1:
                            return NO;
                        case 2:
                            return NO;
                        case 3:
                            return YES;
                        default:
                            return NO;
                    }
                } else {
                    return NO;
                }
            }
        }
    } else {
        return NO;
    }
}

/*
 不实现该方法，则默认与任何手势不共存
 若希望本组件与某些UIPanGestureRecognizer共存，使其不影响本组件的滑动效果:
 1.实现以下方法在对应情况返回YES
 2.在上面的shouldBeRequiredToFail做对应处理
 3.再考虑怎么设计才能可配置且通用
 */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == _dsTapGes) {
        return YES;
    } else if (gestureRecognizer.view == self) {
        if (otherGestureRecognizer.view == self) {
            return NO;
        } else if (otherGestureRecognizer.view == _currentScrollView) {
            //滑动时只滑外部，内部由代码控制。所以不可以与内部捕获的scrollview手势共存，外部优先，取消内部scrollview的手势
            //innerScrollViewFirst情况也不需要共存
            return NO;
        } else {
            if (self.dragScrollDelegate &&
                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:recognizeStrategyForGes:otherGes:)]) {
                NSInteger strategy =\
                [self.dragScrollDelegate dragScrollView:self
                                recognizeStrategyForGes:gestureRecognizer
                                               otherGes:otherGestureRecognizer];
                
                if (strategy != NSNotFound) {
                    return 0 == strategy;
                }
            }
            
            if (self.shouldSimultaneouslyWithOtherGesture) {
                if (self.bods_isDecelerating &&
                    [otherGestureRecognizer isKindOfClass:[UITapGestureRecognizer class]]) {
                    
                    BOOL istapoutscroll = NO;
                    if (_currentScrollView &&
                        _innerSVAttInfCount > 0) {
                        CGFloat curosy = self.contentOffset.y;
                        for (NSInteger infoidx = 0; infoidx < _innerSVAttInfCount; infoidx++) {
                            BODragScrollAttachInfo innerscinfo = _innerSVAttInfAr[infoidx];
                            if (curosy < innerscinfo.dragSVOffsetY) {
                                //当前不符合，下一个会更大，后面不会再符合了，break出来
                                break;
                            } else if (curosy <= innerscinfo.dragSVOffsetY2) {
                                //在内部滑动中
                                NSInteger hier = [self __findViewHierarchy:otherGestureRecognizer.view];
                                if (hier < 2) {
                                    istapoutscroll = YES;
                                }
                                break;
                            }
                        }
                    }
                    
                    //其他view的TapGesture与被ScrollView手势共存时，若shouldFailureOtherTapGestureWhenDecelerating=YES则不共存其他View的本次tap
                    if (istapoutscroll) {
                        return YES;
                    } else {
                        return self.shouldFailureOtherTapGestureWhenDecelerating ? NO : YES;
                    }
                } else {
                    NSInteger hier = [self __findViewHierarchy:otherGestureRecognizer.view];
                    //UIScrollView不共存
                    if ([otherGestureRecognizer.view isKindOfClass:[UIScrollView class]]) {
                        if (hier >= 1) {
                            NSInteger prioritybeg = [self __priorityBehaviorForInnerSV:(id)otherGestureRecognizer.view];
                            switch (prioritybeg) {
                                case -1:
                                    return NO;
                                case 0:
                                    return YES;
                                case 1:
                                    return NO;
                                case 2:
                                    return NO;
                                case 3:
                                    return NO;
                                default:
                                    return NO;
                            }
                        } else {
                            return NO;
                        }
                    } else {
                        if (_currentScrollView && hier >= 2) {
                            /*
                             需要不共存，防止web内部两个scrollview同时滑动
                             有个case：web内又弹了一个可scroll的弹窗，共存会使上下两层都同时滚动
                             */
                            return NO;
                        } else {
                            return YES;
                        }
                    }
                }
            } else {
                return NO;
            }
        }
    } else {
        return NO;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _dsTapGes) {
        if (_lastAniScrollEndTS > 0 &&
            [NSDate date].timeIntervalSince1970 - _lastAniScrollEndTS < 0.1) {
            //刚刚动画被结束了，很可能是因为这次手势导致的，手势结束后需要再执行一次吸附行为，防止停留位置不对
            _needsFixDisplayHWhenTouchEnd = YES;
        } else {
            _needsFixDisplayHWhenTouchEnd = NO;
        }
        _lastAniScrollEndTS = 0;
        
        return _needsFixDisplayHWhenTouchEnd;
    }
    
    if (gestureRecognizer.view == self
        && self.innerScrollViewFirst
        && nil != _currentScrollView) {
        return NO;
    }
    
    if (gestureRecognizer.view == self
        && self.inhibitPanelForWebView
        && _didTouchWebView) {
        return NO;
    }
    
    return YES;
}

/*
 一些情况下比如修改了attach，直接代码执行了滑动，有时希望暂不吸附，有时希望立即吸附
 这里提供一个手动执行吸附的方法
 */
- (void)takeAttach:(BOOL)animated subInfo:(NSDictionary *)subInfo {
    BODragScrollAttachInfo theinfo;
    CGPoint of = self.contentOffset;
    CGPoint inof = of;
    __unused NSInteger scrolltype =\
    [self __scrollViewWillEndDragging:self
                         withVelocity:CGPointZero
                  targetContentOffset:&inof
                           attachInfo:&theinfo];
    
    if (!sf_uifloat_equal(inof.y, of.y)) {
        [self scrollToDisplayH:theinfo.displayH animated:animated];
    }
}

- (void)onTapGes:(UITapGestureRecognizer *)tapGes {
    if (_needsFixDisplayHWhenTouchEnd &&
        UIGestureRecognizerStateEnded == tapGes.state &&
        !self.isDecelerating) {
        
        //若本次点击导致了动画停止，点击结束后，没有触发scroll的惯性，则需要手动进行一次吸附行为，防止停留位置不对
        [self takeAttach:YES subInfo:nil];
    }
}

@end
