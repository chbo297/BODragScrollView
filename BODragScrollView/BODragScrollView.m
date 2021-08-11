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

@end

@implementation UIScrollView (bo_dragScroll)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bo_swizzleMethod(self, @selector(isDragging), @selector(bods_isDragging));
        bo_swizzleMethod(self, @selector(isTracking), @selector(bods_isTracking));
        bo_swizzleMethod(self, @selector(isDecelerating), @selector(bods_isDecelerating));
    });
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

@property (nonatomic, assign) BOOL isScrollAnimating;

@property (nonatomic, strong) NSNumber *needsAnimatedToH;

@end

@implementation BODragScrollView {
    CGRect _lastLayoutBounds;   //记录上次布局的bounds
    BOOL _hasLayoutEmbedView;   //embedView设置后，有没有完成过布局。
    
    NSNumber *_needsDisplayH;   //一些设置displayH的时机View还没有布局，先存下在，布局的时候读取并设置。
    
    BOOL _waitMayDecelerate;
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
    BOOL _forceResetInnerScrollOffsetY;
    NSMutableDictionary *_innerSVBehaviorInfo;
    
    __weak UIControl *_theCtrWhenDecInner; //decelerating时点击了某UIControl，为了不使scrollView的系统机制无效其点击事件，手动传递action
    BOOL _lastScrollIsInner; //最后一次滑动位置变化（包括内外），是否是捕获的内部sv
    BODragScrollTapGes *_dsTapGes;
    
    //触发内部scrollView时会切换到内部scrollView的rate，用该处存储自己的的rate
    UIScrollViewDecelerationRate _curDecelerationRate;
    
    //绑定内部时，会把ScrollToTop设置为NO，如果原本是YES，需要在结束时恢复到YES
    BOOL _needsRecoverScrollVAllowScrollToTop;
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
        _waitMayDecelerate = NO;
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
 有监测到超过1个可捕获的scrollView时，才会往svBehaviorDic里塞内容，否则svBehaviorDic没意义就不塞内容
 */
- (UIScrollView *)__seekTargetScrollViewFrom:(UIView *)view svBehaviorDic:(NSMutableDictionary *)svBehaviorDic {
    
    NSMutableArray<NSMutableDictionary *> *svbehar;
    if (svBehaviorDic) {
        svbehar = @[].mutableCopy;
    }
    
    //优先级：可滑动的ScrollView > tag标记的 > 智能判断高度最高的，都没有传nil; force=YES，相同时也刷新being和end点
    UIScrollView *forwardsc = nil; //被tag标记 可能需要加载的scrollView
    UIScrollView *maxhsc = nil; //高度最大的scrollView
    UIScrollView *thsc = nil;   //寻找第一个可滑动的scrollView
    UIResponder *resp = view;
    while (resp) {
        if (resp == self) {
            break;
        }
        
        if ([resp isKindOfClass:[UIScrollView class]] && [(UIScrollView *)resp isScrollEnabled]) {
            UIScrollView *scv = (UIScrollView *)resp;
            
            BOOL scvalid = YES;
            if (self.dragScrollDelegate &&
                [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:canCatchInnerSV:)]) {
                scvalid = [self.dragScrollDelegate dragScrollView:self canCatchInnerSV:scv];
            }
            
            if (scvalid) {
                NSMutableDictionary *scdic;
                if (svbehar) {
                    scdic = @{}.mutableCopy;
                    [scdic setObject:scv forKey:@"sv"];
                }
                
                NSInteger priority = 0;
                
                UIEdgeInsets inset = sf_common_contentInset(scv);
                //是否能竖向滑动
                if (!thsc
                    && ((scv.contentSize.height + inset.top + inset.bottom)
                        > CGRectGetHeight(scv.bounds))) {
                    thsc = scv;
                    if (!svbehar) {
                        break;
                    }
                } else {
                    if (!forwardsc &&
                        scv.tag > 0 &&
                        (0 == (scv.tag % bo_dragcard_forward_observer_scrollview_tag_r))) {
                        //记录暂不能滑动，但是tag符合forward_observer的scrollview
                        forwardsc = scv;
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
                }
                
                if (scdic) {
                    [scdic setObject:@(priority) forKey:@"priority"];
                    [svbehar addObject:scdic];
                }
            }
        }
        
        resp = resp.nextResponder;
    }
    
    UIScrollView *selsc = (thsc ? : (forwardsc ? : maxhsc));
    
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
        
        [svBehaviorDic setObject:selsc forKey:@"catchSV"];
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
    
    _innerSVBehaviorInfo = nil;
    NSMutableDictionary *svbehaviordic = @{}.mutableCopy;
    UIScrollView *selscv = [self __seekTargetScrollViewFrom:view svBehaviorDic:svbehaviordic];
    if (svbehaviordic.count > 0) {
        if (self.dragScrollDelegate
            && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:innerSVBehavior:)]) {
            [self.dragScrollDelegate dragScrollView:self innerSVBehavior:svbehaviordic];
            selscv = [svbehaviordic objectForKey:@"catchSV"] ? : selscv;
        }
        
        _innerSVBehaviorInfo = svbehaviordic;
    }
    
    [self __setupCurrentScrollView:selscv];
    return [super touchesShouldBegin:touches withEvent:event inContentView:view];
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
    UIView *htv = [super hitTest:point withEvent:event];
    if (event &&
        (self.isScrollAnimating || self.bods_isDecelerating) &&
        htv) {
        //惯性和动画滑动时
        if (_currentScrollView && _lastScrollIsInner) {
            //若滑动的捕获sc内部
            if ([self __findViewHierarchy:htv] > 2) {
                //点击内部需不响应其内部内容
                return _currentScrollView;
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
        if (_needsAnimatedToH) {
            __weak typeof(self) ws = self;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (!ws.needsAnimatedToH) {
                    return;
                }
                CGFloat needsath = ws.needsAnimatedToH.floatValue;
                ws.needsAnimatedToH = nil;
                if (!sf_uifloat_equal(needsath, ws.currDisplayH)) {
                    [ws scrollToDisplayH:needsath animated:YES];
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
        if (self.attachDisplayHAr.count > 0 &&
            self.attachDisplayHAr.lastObject.floatValue > mindh + sf_getOnePxiel()) {
            inset.bottom = self.attachDisplayHAr.lastObject.floatValue - CGRectGetHeight(embedrect);
        }
        
        [self innerSetting:^{
            self.contentInset = inset;
            self.contentOffset = CGPointMake(0, -(selfh - displayh));
            self.contentSize = CGSizeMake(sfw, cardsize.height);
            self.embedView.frame = embedrect;
        }];
        
        [self forceReloadCurrInnerScrollView];
        
        //更新面板展示高度
        self.currDisplayH = CGRectGetHeight(self.bounds) - (CGRectGetMinY(_embedView.frame) - self.contentOffset.y);
    }
    
    [super layoutSubviews];
}

#pragma mark - 设置内部scrollview
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
#if DEBUG
    NSAssert(_embedView != nil, @"embedview should not be nil");
#endif
    
    CGRect embedf = _embedView.frame;
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
            [self __removeObserveForSc:_currentScrollView];
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
        _missAttachAndNeedsReload = 0;
    }
    
    contentsize.height = CGRectGetHeight(embedf);
    [self innerSetting:^{
        self.contentSize = contentsize;
    }];
    embedf.origin.y = 0;
    sfoffset.y = -embedcurrts;
    
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
            [self __addObserveForSc:_currentScrollView];
        }
        
        _lastInnerSCSize = _currentScrollView.contentSize;
        
        CGFloat onepxiel = sf_getOnePxiel();
        UIEdgeInsets cinset = sf_common_contentInset(_currentScrollView);
        CGFloat innertotalsc = 0;
        CGFloat oriinnerosy = _currentScrollView.contentOffset.y;
        //当前内部一共滑了多远
        CGFloat innercursc = oriinnerosy + cinset.top;
        
        NSArray<NSDictionary *> *scinnerinfoar = nil;
        if (self.dragScrollDelegate && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:scrollBehaviorForInnerSV:)]) {
            scinnerinfoar = [self.dragScrollDelegate dragScrollView:self scrollBehaviorForInnerSV:_currentScrollView];
        }
        
        if (!scinnerinfoar) {
            if (nil != self.prefDragInnerScrollDisplayH) {
                scinnerinfoar = @[
                    @{
                        @"displayH": self.prefDragInnerScrollDisplayH,
                        @"beginOffsetY": @(-cinset.top),
                        @"endOffsetY": @(_currentScrollView.contentSize.height + cinset.bottom - CGRectGetHeight(_currentScrollView.bounds))
                    }
                ];
            }
        }
        
        BODragScrollAttachInfo *innerinfoar =\
        (BODragScrollAttachInfo *)malloc(MAX(scinnerinfoar.count, 1) * sizeof(BODragScrollAttachInfo));
        BOOL innerinfoarhascompmem = NO;
        NSInteger innerinfocount = 0;
        
        BOOL specialinnersc = NO;
        //向下-1  向上1  没有是0
        NSInteger innerscmayinother = 0;
        NSInteger findwhichidx = -1;
        
        innertotalsc = (cinset.top
                        + _currentScrollView.contentSize.height
                        + cinset.bottom
                        - CGRectGetHeight(_currentScrollView.bounds));
        
        BOOL caninnerscroll = (innertotalsc > 0);
        
        if (caninnerscroll) {
            //内部可滑动
            
            CGFloat embedmaxts = self.contentInset.top;
            CGFloat embedmints = MIN(sfh - (CGRectGetHeight(embedf) + self.contentInset.bottom),
                                     embedmaxts);
            
#define m_topext (embedcurrts - embedmaxts)
#define m_topextinner (-innercursc)
#define m_bottomext (embedmints - embedcurrts)
#define m_bottomextinner (innercursc - innertotalsc)
            
            CGFloat topbounces = 0;
            CGFloat bottombounces = 0;
            
            //计算innercursc  embedcurrts  topbounces  bottombounces
            if (m_topext > 0 || m_topextinner > 0) {
                //内部或者外部卡片的top bounces了
                BOOL bouncescard = (self.allowBouncesCardTop &&
                                    (self.prefBouncesCardTop || !_currentScrollView.bounces));
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
            
            BOOL innerinfocomplete = NO; //初始化内部scrollView滑动是否完成
            
            if (scinnerinfoar.count > 0) {
                //若指定了内部的滑动行为
                
                BODragScrollAttachInfo lastatinfo;
                CGFloat infoartotalsc = 0;
                BOOL haslastinfo = NO;
                for (NSInteger innerdicidx = 0; innerdicidx < scinnerinfoar.count; innerdicidx++) {
                    NSDictionary *innerscdic = scinnerinfoar[innerdicidx];
                    NSNumber *dhval = [innerscdic objectForKey:@"displayH"];
                    NSNumber *beginval = [innerscdic objectForKey:@"beginOffsetY"];
                    NSNumber *endval = [innerscdic objectForKey:@"endOffsetY"];
                    if ((nil == dhval)
                        || (nil == beginval)
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
                    (BODragScrollAttachInfo){infodh, infosy, YES, infbegin, infend, infosy + inflength};
                    if (haslastinfo && atinf.dragSVOffsetY <= lastatinfo.dragSVOffsetY) {
                        //数据非法
                        continue;
                    }
                    
                    if (findwhichidx < 0) {
                        CGFloat curinnerosy = innercursc - cinset.top;
                        CGFloat curmaydh = (sfh - embedcurrts); //计算完后当前展示高度
                        if (infodh + onepxiel >= curmaydh) {
                            findwhichidx = innerdicidx;
                            
                            //判断当前内部滑动位置是否合法，若不在合适位置，进行复位
                            //scinnerar情况下暂不考虑autoResetInnerSVOffsetWhenAttachMiss 可后续再扩展
                            if (curmaydh < infodh - onepxiel) {
                                if (curinnerosy > infbegin) {
                                    curinnerosy = infbegin;
                                    innercursc = infoartotalsc;
                                    innerscmayinother = 1;
                                } else {
                                    if (haslastinfo) {
                                        if (curinnerosy < lastatinfo.innerOffsetB) {
                                            curinnerosy = lastatinfo.innerOffsetB;
                                        }
                                        innercursc = infoartotalsc;
                                    } else {
                                        innercursc = 0;
                                    }
                                }
                            } else if (curmaydh <= infodh + onepxiel) {
                                if (curinnerosy < infbegin) {
                                    curinnerosy = infbegin;
                                    innercursc = infoartotalsc;
                                } else if (curinnerosy > infend) {
                                    if (innerdicidx < scinnerinfoar.count - 1) {
                                        curinnerosy = infend;
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
                                curinnerosy = infend;
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
                CGFloat dyembedtosc =\
                [_embedView convertRect:_currentScrollView.frame fromView:_currentScrollView.superview].origin.y;
                CGFloat scmints = embedmints + dyembedtosc;
                CGFloat curscts = embedcurrts + dyembedtosc;
                CGFloat scheight = CGRectGetHeight(_currentScrollView.frame);
                //开始滑动内部时，内部scrollView.top距离DragScrollView可展示局域顶部的距离
                CGFloat scinnerts = curscts;
                
#if DEBUG
                //内部bounces时，外部位置需要在最上/下（之上的逻辑需要处理完这种情况）
                if (innercursc < 0) {
                    CGFloat scmaxts = embedmaxts + dyembedtosc;
                    NSAssert(sf_uifloat_equal(curscts, scmaxts), @"innercursc < 0, curscts == scmaxts");
                } else if (innercursc > innertotalsc) {
                    NSAssert(sf_uifloat_equal(curscts, scmints), @"innercursc < 0, curscts(%@) == scmints(%@)", @(curscts), @(scmints));
                }
#endif
                
                BOOL findbeg = NO; //是否找到开始滑动内部时的位置
                
                if (!findbeg && self.attachDisplayHAr.count > 0) {
                    //有吸附点
                    CGFloat beginscdh = 0;
                    CGFloat totalinnerscdh = dyembedtosc + scheight;
                    NSInteger theidx = bo_findIdxInFloatArrayByValue(self.attachDisplayHAr, totalinnerscdh, NO, YES);
                    CGFloat maxexp = 0.3; //滑动内部时，内部至少展示70%（视觉友好），这个数值根据需要再调吧
                    for (NSInteger uidx = theidx; uidx < self.attachDisplayHAr.count; uidx++) {
                        CGFloat thedh = self.attachDisplayHAr[uidx].floatValue;
                        BOOL thisfind = NO;
                        if (thedh >= totalinnerscdh - onepxiel) {
                            //找到能超过内部scrollview的吸附店
                            CGFloat exps = thedh - dyembedtosc - sfh;
                            if (exps <= scheight * maxexp) {
                                thisfind = YES;
                                //有一个吸附点可保证内部scrollView至少展示五分之一（根据需要调整吧），可以作为开始内部滑动的点
                                beginscdh = thedh;
                                findbeg = YES;
                            }
                        }
                        
                        if (thisfind && self.prefDragCardWhenExpand) {
                            //找到了符合的点，但需要找更远的点优先展开整个卡片，继续循环
                            continue;
                        } else {
                            //该点不符合，后面的也不会符合了，break，
                            //或者该点符合，但不需要优先展开卡片，使用第一个符合的点即可，break
                            break;
                        }
                    }
                    
                    
                    if (!findbeg) {
                        NSInteger theminidx = bo_findIdxInFloatArrayByValue(self.attachDisplayHAr, totalinnerscdh, NO, NO);
                        CGFloat themindh = self.attachDisplayHAr[theminidx].floatValue;
                        CGFloat minexps = themindh - dyembedtosc - sfh;
                        if (minexps <= scheight * maxexp) {
                            beginscdh = themindh;
                            findbeg = YES;
                        }
                    }
                    
                    if (findbeg) {
                        CGFloat shouldscbgts = sfh - beginscdh + dyembedtosc;
                        if (curscts < (shouldscbgts - onepxiel)) {
                            if (innercursc < (innertotalsc - onepxiel)) {
                                innercursc = innertotalsc;
                                
                                if (self.autoResetInnerSVOffsetWhenAttachMiss
                                    || _forceResetInnerScrollOffsetY) {
                                    
                                } else {
                                    innerscmayinother = -1;
                                }
                            }
                            
                        } else if (curscts > (shouldscbgts + onepxiel)) {
                            if (innercursc > onepxiel) {
                                innercursc = 0;
                                
                                if (self.autoResetInnerSVOffsetWhenAttachMiss
                                    || _forceResetInnerScrollOffsetY) {
                                    
                                } else {
                                    innerscmayinother = 1;
                                }
                            }
                            
                        } else {
                            specialinnersc = YES;
                        }
                        
                        scinnerts = shouldscbgts;
                    }
                    
                }
                
                CGFloat bofis = dyembedtosc - scinnerts; //开始滑动内部时的offset.y
                bofis = MAX(MIN(-embedmints, bofis), -embedmaxts);
                BODragScrollAttachInfo scinf =\
                (BODragScrollAttachInfo){sfh + bofis, bofis,
                    YES, -cinset.top, -cinset.top + innertotalsc,
                    bofis + innertotalsc};
                //只有一个内部滑动位置
                innerinfoar[0] = scinf;
                innerinfocount = 1;
                //已经是最后一层了，一定保障innerinfocomplete加载完成，后面没有判断了，不需要再管这个标志位了，若后续还要加逻辑可恢复这行
                //                innerinfocomplete = YES;
            }
            
            if (innerinfocount > 0) {
                contentsize.height = CGRectGetHeight(embedf) + innertotalsc;
                _totalScrollInnerOSy = innertotalsc;
                
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
            if (_innerSVAttInfCount > 0) {
                CGFloat addtotalsc = 0;
                for (NSInteger infoidx = 0; infoidx < _innerSVAttInfCount; infoidx++) {
                    BODragScrollAttachInfo theinfo = _innerSVAttInfAr[infoidx];
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
                embedf.origin.y = innercursc;
                sfoffset.y = embedf.origin.y - embedcurrts;
            }
            
            if (!specialinnersc
                && !hasbounces
                && 1 == innerinfocount
                && (0 != innerscmayinother)
                && (!_autoResetInnerSVOffsetWhenAttachMiss && !_forceResetInnerScrollOffsetY)) {
                _missAttachAndNeedsReload = innerscmayinother;
            }
            
            [self innerSetting:^{
                if (0 == self->_missAttachAndNeedsReload) {
                    self->_currentScrollView.contentOffset = inneroffset;
                    self->_lastSetInnerOSy = inneroffset;
                }
            }];
            
        }
        
        if (!innerinfoarhascompmem) {
            //如果以上流程没有把innerinfoar的内存合理托管或者释放，在此释放
            free(innerinfoar);
            //已经是最后一层了，一定保障innerinfoarhascompmem为YES，后面没有判断了，不需要再管这个标志位了，若后续还要加逻辑可恢复这行
            //            innerinfoarhascompmem = YES;
        }
    }
    
    [self innerSetting:^{
        self.contentSize = contentsize;
        self->_embedView.frame = embedf;
        self.contentOffset = sfoffset;
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
            [self __setupCurrentScrollView:_currentScrollView];
            
            if (!self.bods_isTracking &&
                self.bods_isDecelerating &&
                osychange) {
                //如果重置时发现业务方修改了内部的offset
                [self __setupCurrentScrollView:nil];
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
    
    if (_currentScrollView) {
        NSValue *offsetval = [self __checkInnerOSForDH:displayH];
        
        if (offsetval) {
            UIScrollView *thescv = _currentScrollView;
            [self __setupCurrentScrollView:nil];
            [thescv setContentOffset:offsetval.CGPointValue animated:animated];
        } else {
            [self __setupCurrentScrollView:nil];
        }
    }
    
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
                //清空待播动画
                _needsAnimatedToH = nil;
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
                    BODragScrollDecelerateStyle anisel = self.defaultDecelerateStyle;
                    if (self.dragScrollDelegate && [self.dragScrollDelegate respondsToSelector:@selector(dragScrollViewDecelerate:fromH:toH:reason:)]) {
                        anisel = [self.dragScrollDelegate dragScrollViewDecelerate:self
                                                                             fromH:self.currDisplayH
                                                                               toH:displayH
                                                                            reason:reason];
                    }
                    if (BODragScrollDecelerateStyleDefault == anisel) {
                        anisel = self.defaultDecelerateStyle;
                    }
                    
                    if (BODragScrollDecelerateStyleNature == anisel) {
                        self->_waitMayAnimationScroll = YES;
                        self->_animationScrollDidEndBlock = ^{
                            if (completion) {
                                completion();
                            }
                        };
                        [self setContentOffset:os animated:YES];
                    } else {
                        [self __liteAnimateToOffset:os vel:0 completion:^(BOOL isFinish) {
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
                void (^orgbk)(void) = [CATransaction.completionBlock copy];
                [CATransaction setCompletionBlock:^{
                    if (orgbk) {
                        orgbk();
                    }
                    doblock();
                }];
            }
        }
    }
    
    return validdisplayH;
}

- (void)setAttachDisplayHAr:(NSArray<NSNumber *> *)attachDisplayHAr {
    //排序
    _attachDisplayHAr =\
    [attachDisplayHAr sortedArrayUsingComparator:^NSComparisonResult(NSNumber *  _Nonnull obj1, NSNumber *  _Nonnull obj2) {
        return obj1.floatValue - obj2.floatValue;
    }];
    
    //attachDisplayHAr改变后，可展示的最小、最大高度可能会变化，contentinse有可能需要变化
    [self __checkContentInset];
    
    [self forceReloadCurrInnerScrollView];
}

- (void)setPrefDragCardWhenExpand:(BOOL)prefDragCardWhenExpand {
    _prefDragCardWhenExpand = prefDragCardWhenExpand;
    
    [self forceReloadCurrInnerScrollView];
}

- (void)setPrefDragInnerScrollDisplayH:(NSNumber *)prefDragInnerScrollDisplayH {
    _prefDragInnerScrollDisplayH = prefDragInnerScrollDisplayH;
    
    [self forceReloadCurrInnerScrollView];
}

- (void)setMinDisplayH:(NSNumber *)minDisplayH {
    _minDisplayH = minDisplayH;
    //minDisplayH改变后，可展示的最小、最大高度可能会变化，contentinse有可能需要变化
    [self __checkContentInset];
}

- (void)__checkContentInset {
    //如果未layout，layout时在layoutSubviews方法里会统一处理contentinset，不需要提前处理
    if (self.embedView && _hasLayoutEmbedView) {
        //已经layout的情况下，手动检查和修改状态
        UIEdgeInsets inset = UIEdgeInsetsZero;
        CGFloat selfh = CGRectGetHeight(self.bounds);
        CGFloat mindh = (_attachDisplayHAr.count > 0 ?
                         _attachDisplayHAr.firstObject.floatValue
                         :
                         ((nil != self.minDisplayH) ? self.minDisplayH.floatValue : 66));
        inset.top = selfh - mindh;
        
        if (self.attachDisplayHAr.count > 0 && self.embedView) {
            CGFloat maxdh = self.attachDisplayHAr.lastObject.floatValue;
            if (maxdh > mindh) {
                inset.bottom = self.attachDisplayHAr.lastObject.floatValue - CGRectGetHeight(self.embedView.frame);
            }
        }
        
        [self innerSetting:^{
            CGPoint oos = self.contentOffset;
            //setContentInset时系统会自己执行checkcontentOffset行为修改了offset，
            self.contentInset = inset;
            //恢复原先offset
            self.contentOffset = oos;
        }];
    }
}

- (void)forceReloadCurrInnerScrollView {
    //当前已经捕获了内部滑动视图，且初始化过滑动位置，刷新加载
    if (_currentScrollView && _innerSVAttInfCount > 0) {
        [self __setupCurrentScrollView:_currentScrollView];
    }
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
        self.contentOffset = offset;
    } completion:^(BOOL finished) {
        self.isScrollAnimating = NO;
        if (completion) {
            completion(finished);
        }
    }];
    
    if (self.delayCallDisplayHChangeWhenAnimation) {
        void (^orgbk)(void) = [CATransaction.completionBlock copy];
        [CATransaction setCompletionBlock:^{
            if (orgbk) {
                orgbk();
            }
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
    UIEdgeInsets cinset = UIEdgeInsetsZero;
    BOOL triggerinner = NO;
    BOOL isbounces = NO;
    
    if (_innerSVAttInfCount > 0) {
        CGFloat innershouldosy = _currentScrollView.contentOffset.y;
        CGFloat innerminosy = _innerSVAttInfAr[0].innerOffsetA;
        CGFloat innermaxosy = _innerSVAttInfAr[_innerSVAttInfCount - 1].innerOffsetB;
        CGFloat minosy = -self.contentInset.top;
        CGFloat maxosy = MAX(self.contentSize.height + self.contentInset.bottom - CGRectGetHeight(self.bounds),
                             -self.contentInset.top);
        
        CGRect embedf = _embedView.frame;
        CGFloat offsety = self.contentOffset.y;
        if (offsety < minosy) {
            isbounces = YES;
            //头部bounces的情况
            CGFloat topext = minosy - offsety;
            
            if ((self.allowBouncesCardTop &&
                 (self.prefBouncesCardTop || !_currentScrollView.bounces))) {
                innershouldosy = innerminosy - cinset.top;
                embedf.origin.y = 0;
            } else {
                if (_currentScrollView.bounces) {
                    innershouldosy = innerminosy - topext - cinset.top;
                    embedf.origin.y = -topext;
                    
                    isinnersc = YES;
                } else {
                    //内部不支持bounces
                    CGPoint co = self.contentOffset;
                    co.y = minosy;
                    embedf.origin.y = 0;
                    innershouldosy = innerminosy - cinset.top;
                    [self innerSetting:^{
                        self.contentOffset = co;
                    }];
                    isinnersc = NO;
                }
            }
        } else if (offsety < _minScrollInnerOSy) {
            //正常滑动，还没有进入内部滑动范围
            innershouldosy = innerminosy - cinset.top;
            embedf.origin.y = 0;
            
        } else if (offsety <= _maxScrollInnerOSy) {
            //进入了内部滑动范围
            CGFloat cursclength = 0;
            BOOL findtheinfo = NO;
            CGFloat findoffsety = 0;
            for (NSInteger infoidx = 0; infoidx < _innerSVAttInfCount; infoidx++) {
                BODragScrollAttachInfo innerscinfo = _innerSVAttInfAr[infoidx];
                CGFloat infomaxsc = innerscinfo.innerOffsetB - innerscinfo.innerOffsetA;
                if (offsety + sf_getOnePxiel() >= innerscinfo.dragSVOffsetY) {
                    if (infoidx + 1 < _innerSVAttInfCount) {
                        //有下一个
                        BODragScrollAttachInfo nextinfo = _innerSVAttInfAr[infoidx + 1];
                        if (offsety < nextinfo.dragSVOffsetY) {
                            //使用当前
                        } else {
                            cursclength += infomaxsc;
                            continue;
                        }
                    } else {
                        //没下一个
                        //使用当前
                    }
                    
                    CGFloat exty = offsety - innerscinfo.dragSVOffsetY;
                    if (exty > infomaxsc) {
                        cursclength += infomaxsc;
                        innershouldosy = innerscinfo.innerOffsetB;
                        isinnersc = NO;
                    } else {
                        cursclength += exty;
                        innershouldosy = innerscinfo.innerOffsetA + exty;
                        //exty是0的话，标识已经到外部了
                        isinnersc = (exty > 0);
                    }
                    embedf.origin.y = cursclength;
                    
                    findtheinfo = YES;
                    findoffsety = innerscinfo.dragSVOffsetY;
                    
                    break;
                }
                
            }
            
            if (findtheinfo) {
                triggerinner = YES;
            } else {
                innershouldosy = innerminosy - cinset.top;
                embedf.origin.y = 0;
                isinnersc = NO;
            }
            
        } else if (offsety <= maxosy) {
            //正常滑动，不在内部滑动范围
            innershouldosy = innermaxosy - cinset.top;
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
                innershouldosy = innermaxosy - cinset.top;
            } else {
                //bounces内部
                if (_currentScrollView.bounces) {
                    embedf.origin.y = innertotalsc + bottomext;
                    innershouldosy = innermaxosy + bottomext - cinset.top;
                    
                    isinnersc = YES;
                } else {
                    //内部不支持bounces
                    CGPoint co = self.contentOffset;
                    co.y = maxosy;
                    embedf.origin.y = innertotalsc;
                    innershouldosy = innermaxosy - cinset.top;
                    [self innerSetting:^{
                        self.contentOffset = co;
                    }];
                    isinnersc = NO;
                }
            }
        }
        
        CGPoint inneroffset = _currentScrollView.contentOffset;
        inneroffset.y = innershouldosy;
        [self innerSetting:^{
            if (0 == self->_missAttachAndNeedsReload) {
                self->_currentScrollView.contentOffset = inneroffset;
                self->_lastSetInnerOSy = inneroffset;
            }
            self->_embedView.frame = embedf;
        }];
    } else {
        CGFloat coy = self.contentOffset.y;
        CGFloat minosy = -self.contentInset.top;
        CGFloat maxosy =\
        MAX(minosy, self.contentSize.height + self.contentInset.bottom - CGRectGetHeight(self.bounds));
        CGRect embedf = _embedView.frame;
        if (coy > maxosy && !self.allowBouncesCardBottom) {
            isbounces = YES;
            embedf.origin.y = coy - maxosy;
            [self innerSetting:^{
                self->_embedView.frame = embedf;
            }];
        } else if (coy < minosy && !self.allowBouncesCardTop) {
            isbounces = YES;
            embedf.origin.y = coy - minosy;
            [self innerSetting:^{
                self->_embedView.frame = embedf;
            }];
        } else if (embedf.origin.y != 0) {
            embedf.origin.y = 0;
            [self innerSetting:^{
                self->_embedView.frame = embedf;
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
    
    if (triggerinner
        && (0 != _missAttachAndNeedsReload)) {
        _missAttachAndNeedsReload = 0;
        [self __setupCurrentScrollView:_currentScrollView];
    } else if (isbounces && (0 != _missAttachAndNeedsReload)) {
        CGFloat vely = [scrollView.panGestureRecognizer velocityInView:scrollView].y;
        /*
         bounces时
         点在上面，但向下滑了，此时reset点
         点在下面，但向上滑了，此时reset点
         */
        if ((_missAttachAndNeedsReload > 0 && vely > 0)
            || (_missAttachAndNeedsReload < 0 && vely < 0)) {
            _missAttachAndNeedsReload = 0;
            _forceResetInnerScrollOffsetY = YES;
            [self __setupCurrentScrollView:_currentScrollView];
            _forceResetInnerScrollOffsetY = NO;
        }
    }
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
            if (aYESbNO && aYESbNO.boolValue) {
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
                (BODragScrollAttachInfo){adh, dosy, NO, 0, 0, dosy};
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
    for (NSInteger idx = 0 ; idx < count; idx++) {
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
                        if (curidx - 1 >= 0) {
                            taridx = curidx - 1;
                            tarloc = 1;
                        } else {
                            taridx = curidx;
                            tarloc = -1;
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

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    
    BODragScrollAttachInfo theinfo =\
    (BODragScrollAttachInfo){0, 0, NO, 0, 0, 0};
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
    if (11 != scrolltype) {
        if (self.dragScrollDelegate &&
            [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:willTargetToH:reason:)]) {
            [self.dragScrollDelegate dragScrollView:self
                                      willTargetToH:newdh
                                             reason:reason];
        }
        
        //自然滑动方式需要等待scrollViewWillEndDragging结束后，调用scrollViewDidEndDragging时调用进行didenddrag调用
        _waitMayDecelerate = YES;
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
            //先停止惯性
            [scrollView setContentOffset:scrollView.contentOffset animated:NO];
            
            //使用lite动画
            CGPoint toos = *targetContentOffset;
            CGFloat vely = 0;
            if ((toos.y > self.contentOffset.y) == (velocity.y > 0)) {
                //滑动方向和手势方向相同
                vely = fabs(velocity.y);
            }
            _waitMayDecelerate = NO;
            [self __liteAnimateToOffset:toos vel:vely completion:^(BOOL isFinish) {
                if (self.dragScrollDelegate &&
                    [self.dragScrollDelegate respondsToSelector:@selector(dragScrollView:didTargetToH:reason:)]) {
                    [self.dragScrollDelegate dragScrollView:self
                                               didTargetToH:self.currDisplayH
                                                     reason:@"outset-ani"];
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
    
    if (!decelerate && _waitMayDecelerate) {
        _waitMayDecelerate = NO;
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
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (_innerSVAttInfCount > 0 &&
        _currentScrollView.delegate &&
        [_currentScrollView.delegate respondsToSelector:@selector(scrollViewDidEndDecelerating:)]) {
        [_currentScrollView.delegate scrollViewDidEndDecelerating:_currentScrollView];
    }
    
    if (_waitMayDecelerate) {
        _waitMayDecelerate = NO;
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

- (void)fixDisplayHAfterChangeWithAPI {
    BODragScrollAttachInfo theinfo =\
    (BODragScrollAttachInfo){0, 0, NO, 0, 0, 0};
    CGPoint of = self.contentOffset;
    CGPoint inof = of;
    __unused NSInteger scrolltype =\
    [self __scrollViewWillEndDragging:self
                         withVelocity:CGPointZero
                  targetContentOffset:&inof
                           attachInfo:&theinfo];
    if (sf_uifloat_equal(inof.y, of.y)) {
        return;
    } else {
        [self scrollToDisplayH:theinfo.displayH animated:YES];
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
            return NO;
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
            return YES;
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
                                default:
                                    return NO;
                            }
                        } else {
                            return NO;
                        }
                    } else {
                        if (_currentScrollView && hier >= 2) {
                            //与内部scrollview内的手势不共存
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
    return YES;
}

- (void)onTapGes:(UITapGestureRecognizer *)tapGes {
    if (_needsFixDisplayHWhenTouchEnd &&
        UIGestureRecognizerStateEnded == tapGes.state &&
        !self.isDecelerating) {
        //若本次点击导致了动画停止，点击结束后，没有触发scroll的惯性，则需要手动进行一次吸附行为，防止停留位置不对
        [self fixDisplayHAfterChangeWithAPI];
    }
}

@end
