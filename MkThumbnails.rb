#!/usr/bin/ruby -w

#  MkThumbNails - makes image thumbnail files for your web browser
#  Copyright (C) 2013  Lance Arsenault, AGPL(3)

# This file is part of MkThumbnails

# MkThumbNails is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License (AGPL)
# as published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# MkThumbNails is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License at <http://www.gnu.org/licenses/>.

#####################################################################
#
#  This program makes a progression thumbnail images for all files
#  listed in the program arguments, and recurses into directories if
#  a file is a directory.  [ See function print_usage below ]
#
#
#
#  For each PREFIX.type file found this generates the files:
#
#       PREFIX_thumb0.type
#       PREFIX_thumb1.type
#       PREFIX_thumb2.type
#       ...
#       PREFIX_thumbN.type
#
#
#       PREFIX_thumb0.type.html      links to prev, next and PREFIX.type
#       PREFIX_thumb1.type.html      links to prev, next and PREFIX_thumb0.type.html
#       PREFIX_thumb2.type.html      links to prev, next and PREFIX_thumb1.type.html
#       ...
#       PREFIX_thumb[N-1].type.html  links to prev, next and PREFIX_thumb[N-2].type.html
#
#   It also generates an HTML index file with all the smallest image
#   thumbnails.
#
#
#  Run this program with no arguments to see the usage help print out.
#
#  TODO: Handle small images by not just copying to the thumbnails
#  TODO: Port to windows.  Currently works on GNU/Linux.
#
#
#  ChangeLog:
#
#    2013, Sat Oct 5: Don't generate HTML files if there is no new content.
#                     This helps when using rsync to a server, but uses
#                     extra local resources.  This is the default.
#
#####################################################################

require "find"
require "RMagick"
require 'fileutils'
require 'tempfile'

include Magick

#####################################################################
########################## configuration ############################
#####################################################################

# file types suffixes that are considered as images
$fileTypes = ["jpeg","jpg","png", "JPEG", "JPG", "PNG" ]

# makes thumbnail images of the following sizes
#  level                  0          1          2        3
$thumbMaxArea = [ 900 * 900, 600 * 600, 300 * 300, 80 * 80 ]
$numberOfThumbs = $thumbMaxArea.length

# Number of images to show before and after the current image displayed
$numPrevNext = 2

# HTML CSS page colors used in all HTML files generated
$backgroundColor = '#777'
$foregroundColor = '#000'
$spew = $stdout
# We assume that this script has a .js file with it in the same directory
$javaScriptPath = __FILE__.gsub!(/\.rb$/,'.js')
$thumbFileSuffix = '_thumb'
$javaScriptSrc = false

#####################################################################
######################### initialization ############################
#####################################################################

$fileTypes.freeze
$thumbFileSuffix.freeze
$defaultThumbMaxArea = $thumbMaxArea
$prefix = []
$extraLinks = []
$indexFile = ''
$files = []
$defaultNumPrevNext = $numPrevNext
$indexTitle = ''
$defaultIndexTitlePrefix = 'Images from'
$defaultImgAlt = ''

# hashing img:alt by img path
$imgAlt = Hash.new
$imgAltSuffix = '_alt.txt'
$imgAltSuffix.freeze

$captions = Hash.new
$capSuffix = '_cap.htm'
$capSuffix.freeze


#####################################################################
############################# functions #############################
#####################################################################

# Returns the file name of the thumbnail image file
def thumb_img_name(prefix, level, type)
    if level > -1
        return prefix + $thumbFileSuffix + level.to_s + '.' + type
    else
        return prefix + '.' + type
    end
end

# Returns the file name of the thumbnail html file
def thumb_html_name(prefix, level, type)
    return thumb_img_name(prefix, level, type) + '.html'
end

def get_prefixes(f, depth = '')

    # TODO: make this work with File::SEPARATOR in place of '/'

    if f[0,1] == '/'
        $stdout.print "Path: " + f + " is not a relative path\n"
        exit 1
    end

    # Strip off any trailing '/'
    f = f.gsub(/\/+$/, '')

    if File.directory?(f)
        $stdout.print depth, '--- Found Directory: ', f, "\n"
        if f == './' || f == '.'
            files = Dir.glob('*')
            files.delete('.')
            files.delete('..')
        else
            files = Dir.glob(f + '/*')
        end
        files.sort!
        files.each do |ff|
            get_prefixes(ff, depth + '  ')
        end
    elsif File.exist?(f)
        $fileTypes.each do |t|
            regx = /#{'\.' + t + '$'}/
            if f =~ regx
                if not f =~ /#{ $thumbFileSuffix + '[0-9]\.' + t + '$'}/
                    f = f.gsub(regx, '')
                    if depth == ''
                        $stdout.print '--- Found File: ', f, '.', t, "\n"
                    end
                    $prefix.push [ f, t ]
                end
            end
        end
    end
end

def rel_path(from, to)

    lastSlash = -1
    i = 0
    len = from.length
    if len > to.length
        len = to.length
    end

    #print 'from=' + from + ' to=' + to + ' '

    while i < len and from[i] == to[i]
        if to[i, 1] == '/'
            lastSlash = i
        end
        i += 1
    end

    #puts 'i =' + i.to_s

    if lastSlash != -1
        # remove common directory prefixes
        to = to[lastSlash + 1, to.length - lastSlash]
        from = from[lastSlash + 1, from.length - lastSlash]
    end

    #print 'from=' + from + ' to=' + to + ' --> '

    len = from.length
    ret = ''


    i = 0
    while i < len
        if from[i, 1] == '/'
            ret += '../'
        end
        i += 1
    end

    ret += to

    #puts ret
    
    return ret

end

def mk_thumb_images(prefix, type)
    
    # Check for thumbnail images
    i = 0
    while i < $numberOfThumbs
        filename = thumb_img_name(prefix, i, type)
        orgFilename = thumb_img_name(prefix, -1, type)
        if not File.exist?(filename)
            $stdout.print 'Creating: ' + filename + "\n"

            img = Image::read(orgFilename).first

            if (i == $numberOfThumbs - 1) and (defined? icon_image_caption)
                if img.rows * img.columns > $thumbMaxArea[i]
                    img.scale!(Math::sqrt($thumbMaxArea[i]/(img.rows*img.columns).to_f))
                end
                txt = Draw.new
                txt.annotate(img, 0,0,0,0, icon_image_caption(filename)) do
                    self.gravity = Magick::SouthGravity
                    self.pointsize = 24
                    self.font_family = 'Arial'
                    self.stroke = '#fff'
                    self.fill = '#333'
                    self.font_weight = BoldWeight
                end
                img.write filename
            elsif img.rows * img.columns > $thumbMaxArea[i]
                img.scale!(Math::sqrt($thumbMaxArea[i]/(img.rows*img.columns).to_f))
                img.write filename
            else
                FileUtils.cp orgFilename, filename
            end
            img = false
        end
        i += 1
    end
end

def abs(x)
    if x > 0
        return x
    else
        return - x
    end
end

def get_prefix(i)
    if i >= 0 and i < $prefix.length
        return $prefix[i][0]
    elsif i < 0
        while i < 0
            i += $prefix.length
        end
        return $prefix[i][0]
    else
        return $prefix[i % $prefix.length][0]
    end
end

def get_type(i)
    if i >= 0 and i < $prefix.length
        return $prefix[i][1]
    elsif i < 0
        while i < 0
            i += $prefix.length
        end
        return $prefix[i][1]
    else
        return $prefix[i % $prefix.length][1]
    end
end

def mk_thumb_html(i, thumbLevel)

    href = Hash.new
    src = Hash.new

    caption = $captions[rel_path($indexFile, $prefix[i][0])]
    if caption
      caption = File.open(caption, 'rb') { |f| f.read }
      caption = "<div>\n" + caption + "</div>\n"
    else
      caption = ''
    end

    filename = thumb_html_name(get_prefix(i), thumbLevel, get_type(i))
    title = thumb_img_name(get_prefix(i), -1, get_type(i))


    forwardLink = ''
    alt = ''
    imgAltKey = rel_path($indexFile, $prefix[i][0])
    if thumbLevel >= 1
        forwardLink = "\n" + ' | <a href="' +
            rel_path(filename, thumb_html_name(get_prefix(i), thumbLevel - 1 , get_type(i))) +
            '">Larger Image</a>'
    elsif $imgAlt.has_key? imgAltKey
        alt = ' alt="' +
          (File.open($imgAlt[imgAltKey], 'rb') { |f| f.read }).gsub!(/\n+$/,'') + '"'
    elsif $defaultImgAlt != ''
        alt = ' alt="' + $defaultImgAlt + '"'
    end


    j = - $numPrevNext
    while j <= $numPrevNext
        pre = get_prefix(i + j)
        type = get_type(i + j)
        if j != 0
            href[j] = rel_path(filename, thumb_html_name(pre, thumbLevel, type))
            src[j] = rel_path(filename, thumb_img_name(pre, $numberOfThumbs - 1, type))
        elsif thumbLevel != 0
            href[0] = rel_path(filename, thumb_html_name(pre, thumbLevel - 1, type))
            src[0] = rel_path(filename, thumb_img_name(pre, thumbLevel - 1, type))
        else
            href[0] = false
            src[0] = rel_path(filename, thumb_img_name(pre, thumbLevel - 1, type))
        end
        # $stdout.print j.to_s + ' src=' + src[j] + ' href=' + href[j] + "\n"
        j += 1
    end

    #$stdout.print "\n"

    backLink = ''
    if thumbLevel < $numberOfThumbs - 1
        backLink = "\n" + ' | <a href="' +
            rel_path(filename, thumb_html_name(get_prefix(i), thumbLevel + 1, get_type(i))) +
            '">Smaller Image</a>'
    end



    if File.exist?( filename )
        tmpf = Tempfile.new( 'MkThumbnail_' )
        exists = true
    else
        tmpf = File.open( filename, 'w+' )
        exists = false
    end


    extraHTMLHeader = ''
    $extraLinks.each do |a|
        extraHTMLHeader += '<a href="' +
            rel_path(filename, a[0]) + '">' + a[1] + "</a> |\n"

    end


    tmpf.print <<END
<!DOCTYPE html>
<!-- This file was generated by running: #{File::basename($0)} -->
<html lang=en>
    <head>
        <meta charset="UTF-8">
        <title>Image #{title}</title>
        <style>
            body {
                color: #{$foregroundColor};
                background-color: #{$backgroundColor};
            }
       </style>
    </head>
    <body>
#{extraHTMLHeader}
        <a href="#{rel_path(filename, $indexFile)}">Return
            To Image Index Page</a>#{backLink}#{forwardLink}

        <h1>Image #{title}</h1>
        
END

    if $numPrevNext > 0
        tmpf.print '      <div style="margin: 15px 0px">' + "\n"
        j = - $numPrevNext
    
        while j <= $numPrevNext
            if j < -1
                dir = '&lt;&lt; back ' + j.abs.to_s
            elsif j == -1
                dir = '&lt; previous'
            elsif j == 0
                j += 1
                next
            elsif j == 1
                dir = 'next &gt;'
            else
                dir = 'forward ' + j.to_s + ' &gt;&gt;'
            end
            tmpf.print '          <a href="' + href[j] +
                '">' + dir + "</a> &nbsp;\n"
            j += 1
        end
        tmpf.print "      </div>\n\n"
    end


    j = - $numPrevNext
    enlarge = 'enlarge'
    if thumbLevel == 1
        enlarge = 'show full size image'
    end
    j = - $numPrevNext
    direction = 'back'
    while j <= $numPrevNext
        if j != 0
            if j.abs == 1
                imgS = ''
            else
                imgS = 's'
            end
            tmpf.print '        <a href="' +
                href[j] + '" ' +
                'title="' + direction +
                ' ' + abs(j).to_s + ' image' + imgS +
                '"><img src="' +
                src[j] + '"/></a>' + "\n"
        elsif href[0] != false
            tmpf.print '        <a href="' +
                href[j] + '" title="' + enlarge +
                '"><img src="' +
                src[j] + '"/></a>' + "\n"
            direction = 'forward'
        else
            tmpf.print '        <img src="' +
                src[j] + '"' + alt + ' />' + "\n"
            direction = 'forward'
        end
        j += 1
    end


    tmpf.print <<END

#{caption}

    </body>
</html>
END

    if not exists
        # We created a new HTML file
        $stdout.print 'Created: ' + filename + "\n"
        tmpf.close
        return
    end

    # There is an old HTML file but we do not
    # mess with it if there is no difference.
    f = File.open filename, 'r'
    tmpf.rewind
    
    while tmpline = tmpf.gets
        if f.gets != tmpline
            f.close
            $stdout.print 'ReCreating: ' + filename + "\n"
            FileUtils.cp tmpf.path, filename
            return
        end
    end

    if f.gets
        f.close
        $stdout.print 'ReCreating (smaller): ' + filename + "\n"
        FileUtils.cp tmpf.path, filename
        return
    end

    f.close
end


def print_usage

    $stdout.print <<END
Usage: #{$0} \\
    [--add-code PATH] \\
    [--add-link HREF LABEL ...] \\
    [--default-img-alt ALT_TEXT] \\
    [--javascript-src JPATH] \\
    [--number-next N] \\
    [--thumb-areas ARRAY] [--title TITLE] [--number-next N] \\
    TOP_HTML_FILE FILE [FILE ...]

   This program makes a progression of thumbnail images for all files
listed in the program arguments, and recurses into directories if
a file is a directory.  The arguments must to relative paths to
files or directories from the current directory, so that it may
make paths in URLs that are relative, and so the URLs work on web
servers.  We wanted search engines to be able to index our image
and html files, and so we did not use a program to generate the pages
on the server side.

  Make thumbnail image files and thumbnail HTML files for all files listed.
If FILE is a directory all image files in that directory will be considered.
Running this program will remake all the generated HTML files if they
already exist.  Running this program will not regenerate any thumbnail image
files if they already exist.  All filenames (paths) that are arguments must
be relative to the current directory, so that the generated href attributes
still work when the files are moved to any web server in any directory.


                    OPTIONS

    --add-code PATH         include the ruby code in PATH into this running
                            script.  This can be used to override functions
                            like caption_text(image_path).


    --add-link HREF LABEL   The program will add a link to HREF with
                            ancher label LABEL just after <body> in all
                            generated HTML files. This must be the first
                            set of arguments.  HREF is the path relative
                            to the current directory.  The generated href's
                            are fix to work in the directory the HTML is in.
                            You can have any number of --add-link arguments.

    --javascript-src JPATH  Give the relative path to the #{File.basename($0).sub(/\.rb$/, '.js')}
                            javaScript file as JPATH.  This path is relative
                            to the current directory.


    --number-next N         Display N image links before and after the
                            current image being displayed.  The default is:

                                --number-next #{$numPrevNext.to_s}

                            There is still a top index page with all the
                            image thumbnails, each linked to an image display
                            page.

    --thumb-areas ARRAY     pass in the number of thumbnails and there areas
                            where ARRAY is ruby array of the areas.
                            Example:

                                --thumb-areas '[ 400*400, 80*80 ]'

                            will make two thumbnail levels with maximum image
                            areas 400*400 = 160000 and 80*80 = 6400.  The
                            default is:
                                     
                                --thumb-areas '#{$defaultThumbMaxArea.inspect}'

    --title TITLE           Set the title for the HTML index file.  The default
                            title is: "#{$defaultIndexTitlePrefix} ALL_FILE_ARGS"
                            where ALL_FILE_ARGS are all FILE option arguments.

    TOP_HTML_FILE           is the HTML index file name.  It must be a path
                            relative to the current directory.

    FILE                    is an image file, or directory with image files
                            in it.  It must be a path relative to the current
                            directory.

END
    exit 1
end

def get_extraHTMLHeader(filename)
    f = File.open(filename, 'r')
    while line = f.gets
        $extraHTMLHeader += line
    end
    f.close
end

def mk_index_file

    $stdout.print "Printing top HTML index page to: " + 
       rel_path($indexFile, $indexFile) + "\n"
    
    # Print the HTML index page
    f = File.open $indexFile, 'w+'

    if $indexTitle == ''
        title = $prefix.length.to_s + ' ' + $defaultIndexTitlePrefix
        $files.each do |ff|
            title += ' ' + ff
        end
    else
        title = $indexTitle
    end

    extraHTMLHeader = ''
    $extraLinks.each do |a|
        extraHTMLHeader += '<a href="' +
            rel_path($indexFile, a[0]) + '">' + a[1] + "</a> |\n"
    end

    f.print <<END
<!DOCTYPE html>
<!-- This file was generated by running: #{File::basename($0)} -->
<html lang=en>
    <head>
        <meta charset="UTF-8">
END
    if($javaScriptSrc)
        f.print <<END
        <script src="#{rel_path($indexFile, $javaScriptSrc)}"></script>
        <script>
            // Some javaScript configuration
            thumbFileSuffix = '#{$thumbFileSuffix}';
            numberOfThumbs = #{$numberOfThumbs};
            if(MkThumbnails_Setup)
                onload = MkThumbnails_Setup;
        </script>
END
    end
    if($javaScriptSrc && $captions.length > 0)
        f.print <<END
        <script src="#{rel_path($indexFile, $indexFile + '_cap.js')}">
        </script>

END
        cfpath = $indexFile + '_cap.js';
        cf = File.open cfpath, 'w+'
        $stdout.print 'Writing ' + rel_path($indexFile, cfpath) + "\n";
        cf.print <<END
  caption = {
END
        $captions.each do |key,val|
            cf.print <<END
      '#{key}': '#{rel_path($indexFile,val)}',
END
        end
        cf.print <<END
  };
END
        cf.close
    end
    # TODO: The CSS style code is spread over this file
    # and in the javascript.  We need to clean it up.
    # Where should it be?  Clearly there must be some in
    # the javascript and some here so it looks good without
    # javascript turned on.
    f.print <<END
        <title>
            #{title}
        </title>
        <style>
            body {
                color: #{$foregroundColor};
                background-color: #{$backgroundColor};
            }
            div.footer {
                clear: both;
                margin: 16px;
                text-align: center;
            }
            div.img, div.imgcaption {
                text-align: left;
                margin-top: 9px;
                margin-bottom: 9px;
            }
            div.imgcaption {
                border-width: 2px;
                border-color: #333;
                border-style: solid;
                border-top-right-radius: 5px;
                border-bottom-right-radius: 20px;
            }
            span.topbutton {
                padding-top: 10px;
                padding-bottom: 7px;
                padding-left: 20px;
                padding-right: 20px;
            }
            span.bottombutton {
                padding-top: 7px;
                padding-bottom: 10px;
                padding-left: 20px;
                padding-right: 20px;
            } 
            a {
                padding: 0px;
                margin: 0px;
                border-width: 0px;
            }
            img {
                margin: 0px;
                border-width: 0px;
                vertical-align: middle;
                display: inline-block;
            }
            img.viewer {
                padding: 5px;
                margin: 10px;
                background-color: #000;
                float: left;
            }
        </style>
    </head>
    <body>

        <script>
            // Some javaScript to run before page loads
            if(#{$prefix.length} > 0)
                addOverlay(#{$prefix.length.to_s});
        </script>

#{extraHTMLHeader}
        <h1>#{title}</h1> 

END

    title = ''

    $prefix.each do |a|
        img_name = thumb_img_name(a[0], $numberOfThumbs - 1, a[1])
        if defined?(image_title) == 'method'
            title =  'title="' + image_title(img_name) + '" '
        end
        # if $numberOfThumbs == 2 there are 2 thumbnail images
        # For example file.jpg would have
        # file_thumb1.jpg (smallest, thumb level 1) and
        # file_thumb0.jpg (larger, thumb level 0)
        # and the original file and file.jpg (largest, thumb level -1)
        f.print <<END
        <a href="#{rel_path($indexFile, thumb_html_name(a[0], $numberOfThumbs - 1, a[1]))}">
            <img src="#{rel_path($indexFile, img_name)}" #{title}/></a>
END
    end

    f.print <<END

    <script>
        // Some javaScript to run before images load
        MkThumbnails_Setup_onload = false;
        MkThumbnails_Setup();
        MkThumbnails_Setup_onload = true;
    </script>

END



    f.print <<END
    <div class=footer><small>Updated:
         #{(Time.new).strftime('%Y %B %d &nbsp; %I:%M:%S %p (%Z)')}</small></div>
  </body>
</html>
END

end

def printIndexJavaScript(file)

    file.print <<END
        
END

end


def parse_args
    if ARGV.length < 2
        print_usage
    end

    arg = ARGV.shift
    while arg
        if arg == '--add-link'
            if ARGV.length < 2
                print_usage
            end
            arg = ARGV.shift
            $extraLinks.push [ arg, ARGV.shift ]
            if arg[0,1] == '/'
                $stdout.print "Path: " + arg + " is not a relative path\n\n"
                print_usage
            end
        elsif arg == '--javascript-src'
            if ARGV.length < 1
                $stdout.print "Bad --javascript-src option\n\n"
                print_usage
            end
            $javaScriptSrc = ARGV.shift
        elsif arg == '--number-next'
            if ARGV.length < 1
                $stdout.print "Bad --number-next option\n\n"
                print_usage
            end
            $numPrevNext = ARGV.shift.to_i
            if $numPrevNext < 0 or $numPrevNext > 10001
                $stdout.print "Bad --number-next option\n\n"
                print_usage
            end
        elsif arg == '--thumb-areas'
            if ARGV.length < 1
                $stdout.print "Bad --thumb-areas option\n\n"
                print_usage
            end
            # TODO: danger: using eval
            $thumbMaxArea = eval ARGV.shift
            # check that thumbMaxArea is valid
            if not $thumbMaxArea.is_a? Array
                $stdout.print "Bad --thumb-areas option\n\n"
                print_usage
            end
            lastVal = 100000*100000
            $thumbMaxArea.each do |val|
                if (not val.is_a? Integer) or
                    (val >= lastVal) or (val < 0)
                    $stdout.print "Bad --thumb-areas option\n\n"
                    print_usage
                end
                lastVal = val
            end
            $numberOfThumbs = $thumbMaxArea.length
        elsif arg == '--add-code'
            if ARGV.length < 1
                $stdout.print "Bad --add-code option\n\n"
                print_usage
            end
            load ARGV.shift
        elsif arg == '--title'
            if ARGV.length < 1
                $stdout.print "Bad --title option\n\n"
                print_usage
            end
            $indexTitle = ARGV.shift
        elsif arg == '--default-img-alt'
            if ARGV.length < 1
                $stdout.print "Bad --default-img-alt option\n\n"
                print_usage
            end
            $defaultImgAlt = ARGV.shift
        elsif $indexFile == ''
            $indexFile = arg
            if $indexFile[0,1] == '/'
                $stdout.print "Path: " + $indexFile + " is not a relative path\n\n"
                print_usage
            end
        else
            $files.push arg
        end
        arg = ARGV.shift
    end

    # check javaScriptSrc path from indexFile
    if($javaScriptSrc && !(File.exist?($javaScriptSrc)))
        $stdout.print "Bad --javascript-src option\n\n" +
            'path: ' + $javaScriptSrc + " was not found\n\n"            
        print_usage
    end

    $numberOfThumbs.freeze


    if $indexFile == ''
        $stdout.print "TOP_HTML_FILE was not set\n\n"
        print_usage
    end

    $files.each do |ff|
        get_prefixes(ff)
    end

    if $prefix.length == 0
        $stdout.print "No image files found\n"
        exit 1
    end
    if $numPrevNext > $prefix.length - 1
        $numPrevNext = $prefix.length - 1
    end

    $stdout.print 'found ' + $prefix.length.to_s +
        " images files in total\n"

    $prefix.each do |pre|
        path = pre[0] + $capSuffix
        key = rel_path($indexFile, pre[0])
        if(File.exist?(path))
          $captions[key] = path
        end
        path = pre[0] + $imgAltSuffix
        key = rel_path($indexFile, pre[0])
        if(File.exist?(path))
          $imgAlt[key] = path
        end

    end
    $stdout.print "Found " + $captions.length.to_s + " caption files.\n"

end


#####################################################################
############################## main #################################
#####################################################################

# Set up some globel varaibles from the program arguments
parse_args


# check and make thumbnail image files if they do not exist yet
$prefix.each do |a|
    mk_thumb_images(a[0], a[1])
end

# make or remake thumbnail html files
$i = 0
$len = $prefix.length
while $i < $len
    $j = $numberOfThumbs - 1
    while $j >= 0
        mk_thumb_html($i, $j)
        $j -= 1
    end
    $i += 1
end

# make or remake the top index page
mk_index_file

