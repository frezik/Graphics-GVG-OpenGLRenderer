# Copyright (c) 2016  Timm Murray
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without 
# modification, are permitted provided that the following conditions are met:
# 
#     * Redistributions of source code must retain the above copyright notice, 
#       this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright 
#       notice, this list of conditions and the following disclaimer in the 
#       documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
# POSSIBILITY OF SUCH DAMAGE.
package Graphics::GVG::OpenGLRenderer;

# ABSTRACT: Turn a GVG file into OpenGL code
use strict;
use warnings;
use Moose;
use namespace::autoclean;
use Data::UUID;
use Imager::Color;
use Math::Trig 'pi';

has [qw{ circle_segments ellipse_segments }] => (
    is => 'rw',
    isa => 'Int',
    default => 40,
);
has '_glow_count' => (
    traits => ['Counter'],
    is => 'ro',
    isa => 'Int',
    default => 0,
    handles => {
        '_increment_glow' => 'inc',
        '_decrement_glow' => 'dec',
    },
);


sub make_drawer_obj
{
    my ($self, $ast) = @_;

    my ($code, $drawer_pack) = $self->make_code( $ast );
    eval $code or die $@;

    my $obj = $drawer_pack->new;
    return $obj;
}

sub make_code
{
    my ($self, $ast) = @_;
    my $drawer_pack = $self->_make_pack;
    my $code = $self->_make_pack_code( $drawer_pack, $ast );
    return ($code, $drawer_pack);
}

sub _make_pack
{
    my ($self) = @_;
    my $uuid = Data::UUID->new->create_hex;
    my $pack = __PACKAGE__ . '::' . $uuid;
    return $pack;
}

sub _make_pack_code
{
    my ($self, $pack, $ast) = @_;

    my $code = 'package ' . $pack . ';';
    $code .= q!
        use strict;
        use warnings;
        use OpenGL qw(:all);
    !;
    $code .= q!
        sub new
        {
            my ($class) = @_;
            my $self = {};
            bless $self => $class;
            return $self;
        }
    !;

    $code .= 'sub draw {';
    $code .= $self->_make_draw_code( $ast );
    $code .= 'return; }';

    $code .= '1;';
    return $code;
}

sub _make_draw_code
{
    my ($self, $ast) = @_;
    my $code = join( "\n", map {
        my $ret = '';
        if(! ref $_ ) {
            warn "Not a ref, don't know what to do with '$_'\n";
        }
        elsif( $_->isa( 'Graphics::GVG::AST::Line' ) ) {
            $ret = $self->_make_code_line( $_ );
        }
        elsif( $_->isa( 'Graphics::GVG::AST::Rect' ) ) {
            $ret = $self->_make_code_rect( $_ );
        }
        elsif( $_->isa( 'Graphics::GVG::AST::Polygon' ) ) {
            $ret = $self->_make_code_poly( $_ );
        }
        elsif( $_->isa( 'Graphics::GVG::AST::Circle' ) ) {
            $ret = $self->_make_code_circle( $_ );
        }
        elsif( $_->isa( 'Graphics::GVG::AST::Ellipse' ) ) {
            $ret = $self->_make_code_ellipse( $_ );
        }
        elsif( $_->isa( 'Graphics::GVG::AST::Glow' ) ) {
            $self->_increment_glow;
            $ret = $self->_make_draw_code( $_ );
            $self->_decrement_glow;
        }
        else {
            warn "Don't know what to do with " . ref($_) . "\n";
        }

        $ret;
    } @{ $ast->commands });
    return $code;
}

sub _make_code_line
{
    my ($self, $cmd) = @_;
    my $x1 = $cmd->x1;
    my $y1 = $cmd->y1;
    my $x2 = $cmd->x2;
    my $y2 = $cmd->y2;
    my $color = $cmd->color;
    my ($red, $green, $blue, $alpha) = $self->_int_to_opengl_color( $color );

    my $make_line_sub = sub {
        my ($width, $red, $green, $blue, $alpha) = @_;
        my $code = qq!
            glLineWidth( $width );
            glColor4ub( $red, $green, $blue, $alpha );
            glBegin( GL_LINES );
                glVertex2f( $x1, $y1 );
                glVertex2f( $x2, $y2 );
            glEnd();
        !;
        return $code;
    };

    my $code = '';
    if( $self->_glow_count > 0 ) {
        # TODO not really getting the effect I was hoping for. Play around 
        # with it later.
        my @colors1 = $self->_brighten( 1.3, $red, $green, $blue, $alpha );
        my @colors2 = $self->_brighten( 0.6, $red, $green, $blue, $alpha );
        my @colors3 = $self->_brighten( 0.1, $red, $green, $blue, $alpha );
        $code = $make_line_sub->( 3.0, @colors3 );
        $code .= $make_line_sub->( 2.0, @colors2 );
        $code .= $make_line_sub->( 0.5, @colors1 );
    }
    else {
        $code = $make_line_sub->( 1.0, $red, $green, $blue, $alpha );
    }

    return $code;
}

sub _make_code_rect
{
    my ($self, $cmd) = @_;
    my $x = $cmd->x;
    my $y = $cmd->y;
    my $width = $cmd->width;
    my $height = $cmd->height;
    my $color = $cmd->color;
    my ($red, $green, $blue, $alpha) = $self->_int_to_opengl_color( $color );

    my $make_rect_sub = sub {
        my ($width, $red, $green, $blue, $alpha) = @_;
        my $code = qq!
            glLineWidth( $width );
            glColor4ub( $red, $green, $blue, $alpha );
            glBegin( GL_LINES );
                glVertex2f( $x, $y );
                glVertex2f( $x + $width, $y );

                glVertex2f( $x + $width, $y );
                glVertex2f( $x + $width, $y + $height );

                glVertex2f( $x + $width, $y + $height );
                glVertex2f( $x, $y + $height );

                glVertex2f( $x, $y + $height );
                glVertex2f( $x, $y );
            glEnd();
        !;
        return $code;
    };

    my $code = '';
    if( $self->_glow_count > 0 ) {
        # TODO
        $code = $make_rect_sub->( 1.0, $red, $green, $blue, $alpha );
    }
    else {
        $code = $make_rect_sub->( 1.0, $red, $green, $blue, $alpha );
    }

    return $code;
}

sub _make_code_circle
{
    my ($self, $cmd) = @_;
    my $cx = $cmd->cx;
    my $cy = $cmd->cy;
    my $r = $cmd->r;
    my $color = $cmd->color;

    my $poly = Graphics::GVG::AST::Polygon->new({
        cx => $cx,
        cy => $cy,
        r => $r,
        sides => $self->circle_segments,
        rotate => 0,
        color => $cmd->color,
    });

    return $self->_make_code_poly( $poly );
}

sub _make_code_ellipse
{
    my ($self, $cmd) = @_;
    my $cx = $cmd->cx;
    my $cy = $cmd->cy;
    my $rx = $cmd->rx;
    my $ry = $cmd->ry;
    my $color = $cmd->color;
    my $num_segments = $self->ellipse_segments;
    my ($red, $green, $blue, $alpha) = $self->_int_to_opengl_color( $color );

    # See:
    # http://stackoverflow.com/questions/5886628/effecient-way-to-draw-ellipse-with-opengl-or-d3d
    my $make_cmd_sub = sub {
        my ($width, $red, $green, $blue, $alpha) = @_;
        my $theta = 2 * pi / $num_segments;
        my $c = cos( $theta );
        my $s = sin( $theta );
        my $t;

        my $x = 1;
        my $y = 0;

        my $code = qq!
            glLineWidth( $width );
            glColor4ub( $red, $green, $blue, $alpha );
            glBegin(GL_LINE_LOOP);
        !;
        foreach my $i (0 .. $num_segments) {
            my $set_x = $x * $rx + $cx;
            my $set_y = $y * $ry + $cy;
            $code .= qq!
                    glVertex2f( $set_x, $set_y );
            !;

            $t = $x;
            $x = $c * $x - $s * $y;
            $y = $s * $t + $c * $y;
        }

        $code .= q!
            glEnd();
        !;
        return $code;
    };

    my $code = '';
    if( $self->_glow_count > 0 ) {
        # TODO
        $code = $make_cmd_sub->( 1.0, $red, $green, $blue, $alpha );
    }
    else {
        $code = $make_cmd_sub->( 1.0, $red, $green, $blue, $alpha );
    }
    return $code;
}

sub _make_code_poly
{
    my ($self, $cmd) = @_;
    my @coords = @{ $cmd->coords };
    my $color = $cmd->color;
    my ($red, $green, $blue, $alpha) = $self->_int_to_opengl_color( $color );

    my $make_code_sub = sub {
        my ($width, $red, $green, $blue, $alpha) = @_;
        my $code = qq!
            glLineWidth( $width );
            glColor4ub( $red, $green, $blue, $alpha );
            glBegin( GL_LINES );
        !;

        foreach my $i (0 .. $#coords - 1) {
            my $x1 = $coords[$i][0];
            my $y1 = $coords[$i][1];
            my $x2 = $coords[$i+1][0];
            my $y2 = $coords[$i+1][1];

            $code .= qq!
                glVertex2f( $x1, $y1 );
                glVertex2f( $x2, $y2 );
            !;
        }
        $code .= qq!
                glVertex2f( $coords[-1][0], $coords[-1][1] );
                glVertex2f( $coords[0][0], $coords[0][1] );
            glEnd();
        !;
        return $code;
    };

    my $code = '';
    if( $self->_glow_count > 0 ) {
        # TODO
        $code = $make_code_sub->( 1.0, $red, $green, $blue, $alpha );
    }
    else {
        $code = $make_code_sub->( 1.0, $red, $green, $blue, $alpha );
    }

    return $code;
}

sub _int_to_opengl_color
{
    my ($self, $color) = @_;
    my $red = ($color >> 24) & 0xFF;
    my $green = ($color >> 16) & 0xFF;
    my $blue = ($color >> 8) & 0xFF;
    my $alpha = $color & 0xFF;
    return ($red, $green, $blue, $alpha);
}

sub _brighten
{
    my ($self, $multiplier, $red, $green, $blue, $alpha) = @_;
    my $color = Imager::Color->new( $red, $green, $blue, $alpha );
    my ($h, $s, $v, $new_alpha) = $color->hsv;

    $v *= $multiplier;
    $v = 1.0 if $v > 1.0;

    my $hsv_color = Imager::Color->new(
        hue => $h,
        v => $v,
        s => $v,
        alpha => $new_alpha,
    );
    return $hsv_color->rgba;
}


no Moose;
__PACKAGE__->meta->make_immutable;
1;
__END__

