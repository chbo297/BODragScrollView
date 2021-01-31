//
//  PlainVC.m
//  BODragScrollViewDemo
//
//  Created by bo on 2021/1/31.
//

#import "PlainVC.h"
#import "BODragScrollView.h"

@interface PlainVC ()

@property (nonatomic, strong) UIImageView *bgIV;
@property (nonatomic, strong) UIButton *closeBtn;

@end

@implementation PlainVC

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
    UIImageView *cardview = [[UIImageView alloc] initWithFrame:fm];
    cardview.backgroundColor = [UIColor whiteColor];
    cardview.layer.shadowColor = [UIColor colorWithWhite:0 alpha:0.4].CGColor;
    cardview.layer.shadowOpacity = YES;
    cardview.layer.shadowRadius = 6;
    cardview.layer.cornerRadius = 20;
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

@end
