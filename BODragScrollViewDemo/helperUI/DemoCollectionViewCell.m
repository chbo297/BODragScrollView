//
//  DemoCollectionViewCell.m
//  BOTransitionDemo
//
//  Created by bo on 2021/1/2.
//

#import "DemoCollectionViewCell.h"


@implementation DemoHeader

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    [self addSubview:self.label];

    [self.label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self).offset(4);
        make.leading.equalTo(self).offset(9);
    }];
}

- (UILabel *)label {
    if (!_label) {
        _label = [[UILabel alloc] init];
        _label.font = [UIFont systemFontOfSize:19];
        _label.textColor = [UIColor colorWithWhite:0.1 alpha:1];
        _label.textAlignment = NSTextAlignmentLeft;
    }
    return _label;
}

@end

@implementation DemoCollectionViewCell

+ (CGSize)sizeWithWidth:(CGFloat)width {
    return CGSizeMake(width, 64);
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    [self.contentView addSubview:self.label];
    [self.label mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.contentView);
    }];
    
    self.contentView.layer.borderWidth = 1;
    self.contentView.layer.borderColor = [UIColor lightGrayColor].CGColor;
}

- (UILabel *)label {
    if (!_label) {
        _label = [[UILabel alloc] init];
        _label.font = [UIFont boldSystemFontOfSize:14];
        _label.textColor = [UIColor colorWithWhite:0.2 alpha:1];
        _label.textAlignment = NSTextAlignmentCenter;
    }
    return _label;
}


@end
