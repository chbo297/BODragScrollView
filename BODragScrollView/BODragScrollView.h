//
//  BODragScrollView.h
//  BODragScrollView
//
//  Created by bo on 2019/6/27.
//  Copyright © 2019 bo. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

//不同吸附点间切换方式
typedef NS_ENUM(NSUInteger, BODragScrollDecelerateStyle) {
    BODragScrollDecelerateStyleDefault = 0,        //缺省，会使用.defaultDecelerateStyle设定的方式
    BODragScrollDecelerateStyleNature = 1,         //自然滑动(runlooptrackingmode)
    BODragScrollDecelerateStyleCAAnimation = 2,    //非滑动，使用动画过渡(非trackingmodes)
};

/*
 辅助方法，在ar数组中寻找value距离哪一个index的值最近
 
 @nearby 是否先按距离寻找最近的点
 @ceil
 当nearby=NO时，若value在某两点之间，ceil=YES返回较大点的index，ceil=NO返回较小点的index
 当nearby=YES时，会返回value距离最近的点的index，若距离相等，刚好在两点正中央，则根据ceil向上或向下选择
 */
FOUNDATION_EXTERN NSInteger bo_findIdxInFloatArrayByValue(NSArray<NSNumber *> *ar,
                                                          CGFloat value,
                                                          BOOL nearby,
                                                          BOOL ceil);

@class BODragScrollView;

@protocol BODragScrollViewDelegate <UIScrollViewDelegate>

@optional

/*
 布局发生变化的回调
 @first 针对embedView是否首次布局，NO则可能是屏幕大小、BODragScrollView大小发生变化触发的布局
 @willShowHeight 布局完成后embedView即将展示的高度
 @return embedView的size，size.width没有铺满时左右居中
 */
- (CGSize)dragScrollView:(BODragScrollView *)dragScrollView
         layoutEmbedView:(UIView *)embedView
             firstLayout:(BOOL)first
          willShowHeight:(CGFloat *)willShowHeight;

/*
 所有情况下子视图展示高度发生变化都会回调，包括布局变化、手势滑动、被调用scrollToDisplayH:animated:
 @displayH 子视图的展示出的高度
 */
- (void)dragScrollView:(BODragScrollView *)dragScrollView
     displayHDidChange:(CGFloat)displayH;

/*
 scrollview发生了滑动时的回调，手势、scrollToDisplayH:animated:都会触发
 @displayH 子视图的展示出的高度
 @isInner 当前滑动是否embed内部的scrollView
 */
- (void)dragScrollView:(BODragScrollView *)dragScrollView
             didScroll:(CGFloat)displayH
               isInner:(BOOL)isInner;

/*
 指定在某个displayH滑动内部ScrollView的某个区域，
 [
 {  "displayH": NSNumber(float),
 "beginOffsetY": NSNumber(float),
 "endOffsetY": NSNumber(float),
 },
 ...
 ]
 
 例：假如想要让该innerSV在displayH 300时滑动内部的offsety 0-1000，displayH 600时滑动offsety 1000~1200 可以按如下内容返回：
 @[
 @{ @"displayH": @(300),
 @"beginOffsetY": @(0),
 @"endOffsetY": @(1000)
 },
 @{ @"displayH": @(600),
 @"beginOffsetY": @(1000),
 @"endOffsetY": @(1200)]
 }
 ]
 
 1.有返回值时会把该innerScrollView的滑动时机改为该返回的数值
 2.没实现该方法或者返回nil、返回空数组时使用默认滑动方式
 3.该返回值与attachDisplayHAr的关系：
 卡片吸附效果以attachDisplayHAr为主，该返回值只影响内部ScrollView的滑动时机，但若该返回值有不同的displayH时，则在该displayH处也添加吸附行为。
 
 注:请传正确的类型 数组从小到大排列、endOffsetY>beginOffsetY，由外部保证，内部不做合法校验
 */
- (nullable NSArray<NSDictionary *> *)dragScrollView:(BODragScrollView *)dragScrollView
                   scrollBehaviorForInnerSV:(__kindof UIScrollView *)innerSV;

/*
 有些业务需要提前获得scrollview即将滑动的目标位置
 调用scrollToDisplayH:animated:、手势离开屏幕scrollview即将停止/惯性的时机会调用
 willTargetToH只代表当前滑动的意图，随后，滑动意图有可能被手势、点击等中断
 didTargetToH代表每个意图最终完成时的展示高度
 @height 即将滑向该展示高度
 */
- (void)dragScrollView:(BODragScrollView *)dragScrollView
         willTargetToH:(CGFloat)height
                reason:(NSString *)reason;
- (void)dragScrollView:(BODragScrollView *)dragScrollView
          didTargetToH:(CGFloat)height
                reason:(NSString *)reason;

/*
 当发生了非内部滑动、两个吸附点间切换的行为时，
 BODragScrollView可以选择是使用自然的滑动过渡到另一个吸附点（BODragScrollDecelerateStyleNature），
 或是使用[UIView animate]的动画（BODragScrollDecelerateStyleCAAnimation）.
 
 二者区别在于ScrollNatrue使用系统scrollView的滑动效果，滑动过程较自然，并且会触发didScroll方法依次经过各个滑动位置
 滑动过程中会使runloop处于TrackingMode。
 
 BODragScrollDecelerateStyleCAAnimation:
 使用系统的[UIView animationXXX...]方法播放吸附滑动效果，数值上会直接跳跃到目标数值，
 没有中间过程（中间过程数值变化会反映在layer.presentationLayer上用动画播放出来）。
 缺点是效果和随时交互的能力没有StyleNature好。
 优点是动画播放过程是在系统的动画控制进程(BackBoard-GPU)上，即使APP的的主线程进行了大量运算占用了CPU导致主线程卡顿了也不会影响动画播放
 所以如果切换过程中需要做一些CPU运算如修改底图（大量几何运算），可以使用StyleCAAnimation的方式避免CPU的繁忙导致切换效果不流畅。
 
 没有实现该方法时，读取defaultDecelerateStyle
 */
- (BODragScrollDecelerateStyle)dragScrollViewDecelerate:(BODragScrollView *)dragScrollView
                                                  fromH:(CGFloat)fromH
                                                    toH:(CGFloat)toH
                                                 reason:(NSString *)reason;

/*
 当本ScrollView遇到与其它View(非所捕获的scrollView，捕获时当然是本scrollView优先)的手势冲突时，
 0：手势共存
 1：本ScrollView的手势优先
 -1：另外一个手势优先
 3: 不共存，但不指定优先级，优先级走系统默认行为
 NSNotFound: 走默认行为，不干涉
 */
- (NSInteger)dragScrollView:(BODragScrollView *)dragScrollView
    recognizeStrategyForGes:(UIGestureRecognizer *)ges
                   otherGes:(UIGestureRecognizer *)otherGes;

//是否允许捕获该内部scrollView
- (BOOL)dragScrollView:(BODragScrollView *)dragScrollView
       canCatchInnerSV:(UIScrollView *)sv;

/*
 catchAndPriorityInfo中会存放内部默认的行为策略信息，外部可以修改该策略
 注：传出来的该catchAndPriorityInfo容器内的所有Array和Dictionary都是可变类型，可以直接修改其catchSV、priority的值
 
 @{
 // 被捕获的scrollView，可以修改，只能修改为otherSVBehaviorAr中的的scrollView
 @"catchSV": UIScrollView,
 
 // 存放本次手势时，响应链上的其它未被捕获的scrollView，其中的priority用来控制随后的交互行为
 @"otherSVBehaviorAr": @[
 @{
 @"sv": UIScrollView,
 
 // 0：该ScrollView的交互和滑动效果将与DragScrollView共存
 // -1: 该ScrollView的交互与DragScrollView不共存，若冲突则取消该ScrollView的交互响应
 // 1: 该ScrollView的交互与DragScrollView不共存，若冲突则取消该DragScrollView的交互响应
 // 2：该ScrollView的交互与DragScrollView不共存, 但冲突时不做强制处理，交给系统默认行为(内部的横滑scrollView默认使用该优先级，用来保障横滑和竖滑不共存，并视滑动方向自动选择哪个有效)
 // 3: 融入交互滑动中
 @"priority": @(-1/0/1/2/3)
 }
 ]
 }
 */
- (void)dragScrollView:(BODragScrollView *)dragScrollView
  catchAndPriorityInfo:(NSMutableDictionary *)catchAndPriorityInfo;

//对于该displayH，是否消除吸附行为
- (BOOL)dragScrollView:(BODragScrollView *)dragScrollView
   shouldMisAttachForH:(CGFloat)displayH;

/*
 视障、旁白的处理方法
 return：
 nil 业务不处理，由控件默认行为处理（根据方向由小到大、由大到小，并智能判定内里是否有scrollview进行滑动）
 YES 业务已处理，控件无需再处理
 NO  业务未处理，控件继续默认行为(不再尝试对内里的scrollview进行处理)
 */
- (nullable NSNumber *)dragScrollView:(BODragScrollView *)dragScrollView accessibilityScroll:(UIAccessibilityScrollDirection)direction;

@end


/*
 * 示例：
 * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * UIViewController *YourVC;
 * UIView *YourDisplayView;
 *
 * BODragScrollView *dragScrollView = [BODragScrollView new];
 * [YourVC.view addSubview:dragScrollView];
 *
 * dragScrollView.embedView = YourDisplayView;
 *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 * 此时图层结构如下:
 * BODragScrollView: 铺满在页面上面(本身不阻碍下层View的手势交互)，
 * embedView: 作为一个子View可以上下拖拽并和EmbedView内部的scrollView友好衔接，
 * currDisplayH: 表示EmbedView当前在BODragScrollView中展示出来的高度
 * 注：上下滑动过程中，EmbedView本身的size不变化，
 * 上下滑动变化的是EmbedView在DragScrollView中展示出来的高度(即CurrDisplayH)，
 * 没有展示出来的部分是因为超出了DragScrollView的bounds
 * 当然，业务方需要改变其size时，可以手动改变embedView的高度，然后重新调用setEmbedView让控件重新加载
 *
 *       ┌─────────────────────────┐
 *       │                         │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │    BODragScrollView     │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │                         │
 *       │┌───────────────────────┐│   ┐
 *       ││                       ││   │
 *       ││                       ││   │
 *       ││                       ││   │
 *       ││       EmbedView       ││   │- CurrDisplayH
 *       ││                       ││   │
 *       ││                       ││   │
 *       ││                       ││   │
 *       └+───────────────────────+┘   ┘
 *        │                       │
 *        │                       │
 *        │                       │
 *        │                       │
 *        │                       │
 *        │                       │
 *        │                       │
 *        └───────────────────────┘
 *
 *
 *  开发和接入过程该组件不关心EmbedView内部业务逻辑(内部的交互、scrollView、webView、collectionView、tableView等都不关心)
 *  运行过程中，组件会自动对接内部的scrollView完成交互处理
 *
 *  设置吸附点：
 *  如果想要设置页面初始的展示高度，直接设置currDisplayH即可
 *  如果想要设置embedView在滑动到顶、到底时的高度，或者中间吸附停留位置，设置attachDisplayHAr
 *  比如有底部、半屏、完全展开三个状态，假设高度分别为100、200、600：.attachDisplayHAr = @[@100, @200, @600]
 *
 */
@interface BODragScrollView : UIScrollView

/*
 //要嵌入的子视图
 //外部直接set即可
 */
@property (nonatomic, strong, nullable) UIView *embedView;

/*
 获取当前embed view展示的高度（embed view顶部到BODragScrollView底部的距离）
 可以利用辅助方法 bo_findIdxInFloatArrayByValue 从 attachDisplayHAr 数组中得到当前展示在第几个吸附点附近
 */
@property (nonatomic, readonly) CGFloat currDisplayH;

/*
 当未进行布局时，若调用scrollToDisplayH:方法，currDisplayH并不会立即改变，因为还没有布局和展示
 此时会将willLayoutToDisplayH置为即将要生效的高度，布局的时候进行应用。
 */
@property (nonatomic, readonly, nullable) NSNumber *willLayoutToDisplayH;

/*
 当未进行布局时，若调用scrollToDisplayH:animated:YES方法，currDisplayH并不会立即改变，因为还没有布局和展示
 此时会将needsAnimatedToH置为即将要执行的动画到达的高度，布局后开启动画
 */
@property (nonatomic, readonly, nullable) NSNumber *needsAnimatedToH;

/*
 滑动到指定位置（展示高度）
 return:
 执行方法后，即将或已经到达的displayH
 （若当前View还没有渲染到屏幕上，并不会立即生效，会在layoutsubviews后displayH才生效，
 生效之前高度会反映在willLayoutToDisplayH属性上）
 
 有几种情况返回的数值和传入的displayH会不一致：
 1.调用时并没有embedview，则返回0，因为没有内容可以展示。
 2.受attachDisplayHAr以及prefBouncesCardTop、Bottom的约束，当embedview有最小/最大展示高度且不能bounces时，
 传入的displayH超出了最小/最大值则只会滑动到对应的最值。
 */

- (CGFloat)scrollToDisplayH:(CGFloat)displayH animated:(BOOL)animated;

- (CGFloat)scrollToDisplayH:(CGFloat)displayH
                   animated:(BOOL)animated
                 completion:(void (^ __nullable)(void))completion;

- (CGFloat)scrollToDisplayH:(CGFloat)displayH
                   animated:(BOOL)animated
                    subInfo:(nullable NSDictionary *)subInfo
                 completion:(void (^ __nullable)(void))completion;

//设置子视图吸附点（停留位置），每个数字标识内嵌View展示的高度（要求传入的每个数值大于0且从小到大排列）
@property (nonatomic, strong, nullable) NSArray<NSNumber *> *attachDisplayHAr;
/*
 见该方法的注释：
 - (BODragScrollDecelerateStyle)dragScrollViewDecelerate:(BODragScrollView *)dragScrollView
 fromH:(CGFloat)fromH
 toH:(CGFloat)toH
 reason:(NSString *)reason;
 
 default: BODragScrollDecelerateStyleNature
 */
@property (nonatomic, assign) BODragScrollDecelerateStyle defaultDecelerateStyle;

//在指定范围内消除吸附行为，使embedView可以自由滑动，该属性只有在attachDisplayHAr有值时才会被用到
//CGPoint数组，x代表起始位置，y代表终点位置。例: 在100~200之前消除吸附行为 则传值： @[[NSValue valueWithCGPoint:CGPointMake(100, 200)],]
@property (nonatomic, strong, nullable) NSArray<NSValue *> *misAttachRangeAr;

//事件回调的代理
@property (nonatomic, weak, nullable) id<BODragScrollViewDelegate> dragScrollDelegate;

/*
 attachDisplayHAr有值时minDisplayH属性无效
 没有设置attachDisplayHAr时，默认最大展示高度是embed的高度，最小高度读取minDisplayH，没读到默认66
 （该值需小于embed的高度）
 */
@property (nonatomic, strong, nullable) NSNumber *minDisplayH;

/*
 embedView内部的scrollView内还嵌套scrollView时，定义其滑动位置的行为
 nil: 默认判定，优先展开全部子视图后再开始滑或者从当前触发位置开始滑，当prefDragCardWhenExpand=YES时，子视图在父视图中展示到最上部再开始滑子视图。
 0: 从当前位置开始，优先子视图，再父视图
 1: 子视图在父视图中展示全就可以开始滑子视图了
 2: 子视图在父视图中展示到最上部再开始滑子视图
 */
@property (nonatomic, strong, nullable) NSNumber *nestingScrollStyle;

/*
 默认是NO
 设YES后，业务内部的ScrollView优先相应，卡片交互效果不再联动。
 */
@property (nonatomic, assign) BOOL innerScrollViewFirst;

/*
 默认是NO
 设YES后，若检测到在webView中的多层可竖滑scrollView交互，则不捕获
 避免影响web内多层scrollView的特殊效果
 */
@property (nonatomic, assign) BOOL ignoreWebMulInnerScroll;

//是否自动展示内部scrollview的Indictor
@property (nonatomic, assign) BOOL autoShowInnerIndictor;

/*
 以下两个状态用来设置在有手动设置的吸附点时如何选择开始滑动内部scrollView的位置
 默认识别策略：优先全部展示内部ScrollView后再开始找一个最近的吸附点开始滑动内部ScrollView
 */
@property (nonatomic, assign) BOOL prefDragCardWhenExpand; //default: false 当设置为true时，优先滑动卡片视图，卡片视图都展开后后才滑动其内部的scrollView
@property (nonatomic, strong, nullable) NSNumber *prefDragInnerScrollDisplayH; //default: nil 当设置值后，组件优先选择此处开始滑动内部scrollView
@property (nonatomic, assign) BOOL prefDragInnerScroll; //default: false 当设置为true时，优先滑动当前落指处的内部scrollview开始滑动, 只有false时再设置prefDragCardWhenExpand才有效

/*
 在没有实现代理方法 dragScrollView:recognizeStrategyForGes:otherGes: 时 shouldSimultaneouslyWithOtherGesture属性才会生效，
 系统的scrollView默认是不与其它View的Gesture共存的，会有冲突导致二者有一个失效
 是否与其它View(非scrollView)的ges共存，
 YES: 二者共存
 NO: 二者不可共存，最终是响应本scrollView的交互还是其他View的Gesture不详（UIKit内部行为）
 default: YES
 如果想要精确控制何时响应本scrollView的手势，何时优先其他View的手势，请使用代理方法(dragScrollView:recognizeStrategyForGes:otherGes:)
 */
@property (nonatomic, assign) BOOL shouldSimultaneouslyWithOtherGesture;

/*
 decelerating过程中，点击内部时（这种点击会优先把本scrollView的滑动停止），在二者可共存时是否把此次内部tapGesture无效。
 （这个设置对webView暂时没有办法，webView中系统似乎做了一些特殊的行为超越了手势、touch事件）
 default:YES
 */
@property (nonatomic, assign) BOOL shouldFailureOtherTapGestureWhenDecelerating;

/*
 比如用户把内部scrollView滑动一半儿，又拖拽面板到了其它位置，又开始滑内部SV，此时是否自动将内部SV置到顶或者底。default: false
 YES: 自动将内部SV置到顶或者底
 NO: 不修改内部SV滑动位置，允许从当前落指位置开始滑动内部,
 */
@property (nonatomic, assign) BOOL autoResetInnerSVOffsetWhenAttachMiss;

//设置顶部、底部的bounces行为
@property (nonatomic, assign) BOOL prefBouncesCardTop; //default: true 手势向下滑时，若超出bounces、有内部scrollview，是否优先bounces卡片视图
@property (nonatomic, assign) BOOL prefBouncesCardBottom; //default: false allowBouncesCardBottom为true时，手势向上滑，若超出bounces、有内部scrollview，是否优先bounces卡片视图
@property (nonatomic, assign) BOOL allowBouncesCardTop; //default: true 是否允许卡片视图顶部bounces，若为false，prefBouncesCardTop无效
@property (nonatomic, assign) BOOL allowBouncesCardBottom; //default: true 是否允许卡片视图底部bounces，若为false，prefBouncesCardBottom无效

//是否正在UIView animate 的block里，当外部接收到displayHDidChange等变化时，若此变化是动画中的block导致的，则此时animationSetting为YES
@property (nonatomic, readonly) BOOL animationSetting;

/*~~~~以下数值调节滑动手感~~~~*/
//滑动使用BODragScrollDecelerateStyleCAAnimation时的动画速率单位是pt/s, 数值在100-10000之间
//默认值1000，全屏态切换半屏幕态大概0.35s左右
@property (nonatomic, assign) CGFloat caAnimationSpeed;
//default 0.12
@property (nonatomic, assign) CGFloat caAnimationBaseDur;
//default 0.32
@property (nonatomic, assign) CGFloat caAnimationMaxDur;
//default YES
@property (nonatomic, assign) BOOL caAnimationUseSpring;

@property (nonatomic, assign) BOOL delayCallDisplayHChangeWhenAnimation;
@property (nonatomic, assign) BOOL needsAnimationWhenDelayCall;

@end

NS_ASSUME_NONNULL_END

