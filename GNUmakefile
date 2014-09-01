
YUI = yui-compressorrr
JSCOMPILE = $(YUI) --type js --line-break 50
#JSCOMPILE = cat
CSSCOMPILE = $(YUI) --type css --line-break 50



jsp_built_files = $(sort $(patsubst %.jsp, %.js, $(wildcard *.jsp)))

built_files =$(jsp_built_files)

clean_files = $(sort $(built_files) $(extra_clean_files))


########################################################
# GNU pseudo rules
########################################################

.SUFFIXES:
.SUFFIXES: .phtml .html .htm .phtm .jsp .js

.SECONDARY:

.DEFAULT_GOAL := build

# remove some useless moldy GNU make implicit rules
% : s.%
% : RCS/%,v
% : SCCS/s.%
% : %,v
% : RCS/%


##########################################################
# rules start here
##########################################################

.jsp.js:
	$(JSCOMPILE) $< > $@ || rm -f $@

build: $(built_files)

clean:
	rm -f $(clean_files)

