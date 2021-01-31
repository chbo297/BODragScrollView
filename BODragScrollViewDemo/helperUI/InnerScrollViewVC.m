//
//  InnerScrollViewVC.m
//  BODragScrollViewDemo
//
//  Created by bo on 2021/1/31.
//

#import "InnerScrollViewVC.h"
#import "BODragScrollView.h"
#import "DemoCollectionViewCell.h"

@interface InnerScrollViewVC () <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource, BODragScrollViewDelegate>

@property (nonatomic, strong) NSArray *dataAr;
@property (nonatomic, strong) UICollectionView *collectionView;

@property (nonatomic, strong) UIImageView *bgIV;
@property (nonatomic, strong) UIButton *closeBtn;

@end

@implementation InnerScrollViewVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.bgIV.image = [UIImage imageNamed:@"demophoto"];
    [self.view addSubview:self.bgIV];
    self.bgIV.backgroundColor = [UIColor lightGrayColor];
    
    [self.bgIV mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    
    self.view.addSubview(self.closeBtn);
    self.closeBtn.mas_makeConstraints(^(MASConstraintMaker *make) {
        if (@available(iOS 11.0, *)) {
            make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(44);
        } else {
            make.top.equalTo(self.view.mas_top).offset(44);
        }
        make.leading.equalTo(self.view).offset(20);
    });
    
    __weak typeof(self) ws = self;
    self.closeBtn.cc_setTouchUpInSideDo(^(UIButton *bt) {
        if (ws.presentingViewController) {
            [ws.presentingViewController dismissViewControllerAnimated:YES completion:nil];
        } else if (ws.navigationController) {
            [ws.navigationController popViewControllerAnimated:YES];
        }
    });
    
    BODragScrollView *sv = [BODragScrollView new];
    [self.view addSubview:sv];
    sv.mas_makeConstraints(^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    });
    
    UIView *cardview = [self obtainCardView];
    sv.embedView = cardview;
    sv.dragScrollDelegate = self;
    
    CGFloat min = 100;
    CGFloat max = cardview.bounds.size.height;
    if (self.hasAttachPt) {
        CGFloat mid = (max + min) / 2.f;
        sv.attachDisplayHAr = @[@(min), @(mid), @(max)];
    } else {
        sv.attachDisplayHAr = @[@(min), @(max)];
        sv.decelerationRate = UIScrollViewDecelerationRateNormal;
    }
}

- (UIView *)obtainCardView {
    CGRect fm = self.view.bounds;
    fm.size.height -= 120;
    UIView *cardview = [[UIView alloc] initWithFrame:fm];
    cardview.backgroundColor = [UIColor whiteColor];
    cardview.layer.cornerRadius = 20;
    cardview.layer.masksToBounds = YES;
    
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    [cardview addSubview:self.collectionView];
    [self.collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(cardview);
    }];
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
    
    return cardview;
}


- (UIImageView *)bgIV {
    if (!_bgIV) {
        _bgIV = [[UIImageView alloc] init];
    }
    return _bgIV;
}

- (UIButton *)closeBtn {
    if (!_closeBtn) {
        _closeBtn = UIButton.cc_button(UIButtonTypeSystem);
        _closeBtn.cc_setBgImage([UIImage imageNamed:@"white_close"]);
    }
    return _closeBtn;
}

- (UICollectionView *)collectionView {
    if (!_collectionView) {
        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                             collectionViewLayout:[UICollectionViewFlowLayout new]];
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.alwaysBounceVertical = YES;
        if (@available(iOS 11.0, *)) {
            _collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        [_collectionView registerClass:[DemoCollectionViewCell class] forCellWithReuseIdentifier:@"ds"];
        [_collectionView registerClass:[DemoHeader class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"dh"];
        
    }
    return _collectionView;
}

#pragma mark - collection view delegate

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 0;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsZero;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(collectionView.bounds.size.width, 60);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 40;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DemoCollectionViewCell *cell =\
    [collectionView dequeueReusableCellWithReuseIdentifier:@"ds" forIndexPath:indexPath];
    cell.label.text = [NSString stringWithFormat:@"%@", @(indexPath.row)];
    return cell;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

#pragma mark -

- (NSArray<NSDictionary *> *)dragScrollView:(BODragScrollView *)dragScrollView
                   scrollBehaviorForInnerSV:(__kindof UIScrollView *)innerSV {
    if (self.specialScrollRange) {
        return @[
            @{ @"displayH": @(100),
               @"beginOffsetY": @(0),
               @"endOffsetY": @(0)
            },
            @{ @"displayH": @(300),
               @"beginOffsetY": @(0),
               @"endOffsetY": @(1200),
            },
            @{ @"displayH": @(dragScrollView.embedView.frame.size.height),
               @"beginOffsetY": @(1200),
               @"endOffsetY": @(innerSV.contentSize.height - innerSV.bounds.size.height)
            }];
    } else {
        return nil;
    }
}

@end
