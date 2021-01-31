//
//  ViewController.m
//  BODragScrollViewDemo
//
//  Created by bo on 2021/1/28.
//

#import "ViewController.h"
#import "DemoCollectionViewCell.h"
#import "PlainVC.h"
#import "InnerScrollViewVC.h"

static CGSize sf_cell_size;

@interface ViewController () <UICollectionViewDelegateFlowLayout, UICollectionViewDataSource>

@property (nonatomic, strong) NSArray *dataAr;
@property (nonatomic, strong) UICollectionView *collectionView;

@end

@implementation ViewController

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

- (void)viewDidLoad {
    [super viewDidLoad];
    sf_cell_size = CGSizeMake(108, 135);
    __weak typeof(self) ws = self;
    self.dataAr = @[
        @{
            @"title": @" ",
            @"dataAr": @[
                    @{
                        @"title": @"卡片式交互-自由滑动",
                        @"cellSetupBlock": ^(DemoCollectionViewCell *cell){
                            cell.imageV.layer.cornerRadius = 54;
                            cell.imageV.layer.masksToBounds = YES;
                        },
                        @"block": ^(DemoCollectionViewCell *cell){
                            PlainVC *vc = [PlainVC new];
                            vc.modalPresentationStyle = UIModalPresentationFullScreen;
                            [ws.navigationController pushViewController:vc animated:YES];
                        }
                    },
                    
                    @{
                        @"title": @"卡片式交互-有吸附点",
                        @"cellSetupBlock": ^(DemoCollectionViewCell *cell){
                            cell.imageV.layer.cornerRadius = 54;
                            cell.imageV.layer.masksToBounds = YES;
                        },
                        @"block": ^(DemoCollectionViewCell *cell){
                            PlainVC *vc = [PlainVC new];
                            vc.hasAttachPt = YES;
                            vc.modalPresentationStyle = UIModalPresentationFullScreen;
                            [ws.navigationController pushViewController:vc animated:YES];
                        }
                    },
                    
                    @{
                        @"title": @"卡片内嵌ScrollView-自由滑动",
                        @"cellSetupBlock": ^(DemoCollectionViewCell *cell){
                            cell.imageV.layer.cornerRadius = 54;
                            cell.imageV.layer.masksToBounds = YES;
                        },
                        @"block": ^(DemoCollectionViewCell *cell){
                            InnerScrollViewVC *vc = [InnerScrollViewVC new];
                            vc.hasAttachPt = NO;
                            vc.modalPresentationStyle = UIModalPresentationFullScreen;
                            [ws.navigationController pushViewController:vc animated:YES];
                        }
                    },
                    
                    @{
                        @"title": @"卡片内嵌ScrollView-有吸附点",
                        @"cellSetupBlock": ^(DemoCollectionViewCell *cell){
                            cell.imageV.layer.cornerRadius = 54;
                            cell.imageV.layer.masksToBounds = YES;
                        },
                        @"block": ^(DemoCollectionViewCell *cell){
                            InnerScrollViewVC *vc = [InnerScrollViewVC new];
                            vc.hasAttachPt = YES;
                            vc.modalPresentationStyle = UIModalPresentationFullScreen;
                            [ws.navigationController pushViewController:vc animated:YES];
                        }
                    },
                    
                    @{
                        @"title": @"卡片内嵌ScrollView-指定内部滑动范围",
                        @"cellSetupBlock": ^(DemoCollectionViewCell *cell){
                            cell.imageV.layer.cornerRadius = 54;
                            cell.imageV.layer.masksToBounds = YES;
                        },
                        @"block": ^(DemoCollectionViewCell *cell){
                            InnerScrollViewVC *vc = [InnerScrollViewVC new];
                            vc.hasAttachPt = NO;
                            vc.specialScrollRange = YES;
                            vc.modalPresentationStyle = UIModalPresentationFullScreen;
                            [ws.navigationController pushViewController:vc animated:YES];
                        }
                    },
            ]
        }
    ];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    
    [self.view addSubview:self.collectionView];
    [self.collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        if (@available(iOS 11.0, *)) {
            make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop);
            make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom);
        } else {
            make.top.equalTo(self.view.mas_top);
            make.bottom.equalTo(self.view.mas_bottom);
        }
        make.leading.trailing.equalTo(self.view);
    }];
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    if (@available(iOS 13.0, *)) {
        return UIStatusBarStyleDarkContent;
    } else {
        return UIStatusBarStyleDefault;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
}

#pragma mark - collection view delegate

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    CGFloat w = (CGRectGetWidth(collectionView.bounds) - 2.f * sf_cell_size.width) / 3.f;
    return w;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return 25;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    CGFloat w = (CGRectGetWidth(collectionView.bounds) - 2.f * sf_cell_size.width) / 3.f;
    return UIEdgeInsetsMake(0, w, 40, w);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [DemoCollectionViewCell sizeWithWidth:collectionView.bounds.size.width];
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    DemoHeader *header = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                                                            withReuseIdentifier:@"dh"
                                                                   forIndexPath:indexPath];
    NSDictionary *datadic = self.dataAr[indexPath.section];
    header.label.text = datadic[@"title"];
    return header;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section {
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 40);
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return self.dataAr.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [[self.dataAr[section] objectForKey:@"dataAr"] count];
}

- (NSDictionary *)dataDicFor:(NSIndexPath *)indexPath {
    return self.dataAr[indexPath.section][@"dataAr"][indexPath.row];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DemoCollectionViewCell *cell =\
    [collectionView dequeueReusableCellWithReuseIdentifier:@"ds" forIndexPath:indexPath];
    cell.imageV.image = [UIImage imageNamed:@"testImg"];
    NSDictionary *datadic = [self dataDicFor:indexPath];
    NSString *title = [datadic objectForKey:@"title"];
    cell.label.text = title;
    void (^cellbk)(DemoCollectionViewCell *cell) = [datadic objectForKey:@"cellSetupBlock"];
    if (cellbk) {
        cellbk(cell);
    }
    return cell;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    DemoCollectionViewCell *cell = (id)[collectionView cellForItemAtIndexPath:indexPath];
    if (![cell isKindOfClass:[DemoCollectionViewCell class]]) {
        cell = nil;
    }
    NSDictionary *datadic = [self dataDicFor:indexPath];
    void (^bk)(DemoCollectionViewCell *cell) = [datadic objectForKey:@"block"];
    if (bk) {
        bk(cell);
    }
    
    return NO;
}

@end
