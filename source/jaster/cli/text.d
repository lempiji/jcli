/// Contains various utilities for displaying and formatting text.
module jaster.cli.text;

import std.typecons : Flag;

/// Contains options for the `lineWrap` function.
struct LineWrapOptions
{
    /++
     + How many characters per line, in total, are allowed.
     +
     + Do note that the `linePrefix`, `lineSuffix`, as well as leading new line characters are subtracted from this limit,
     + to find the acutal total amount of characters that can be shown on each line.
     + ++/
    size_t lineCharLimit;

    /++
     + A string to prefix each line with, helpful for automatic tabulation of each newly made line.
     + ++/
    string linePrefix;

    /++
     + Same as `linePrefix`, except it's a suffix.
     + ++/
    string lineSuffix;
}

/++
 + Wraps a piece of text into seperate lines, based on the given options.
 +
 + Throws:
 +  `Exception` if the char limit is too small to show any text.
 +
 + Notes:
 +  Currently, this performs character-wrapping instead of word-wrapping, so words
 +  can be split between multiple lines. There is no technical reason for this outside of I'm lazy.
 +
 +  For every line created from the given `text`, the starting and ending spaces (not whitespace, just spaces)
 +  are stripped off. This is so the user doesn't have to worry about random leading/trailling spaces, making it
 +  easier to format for the general case (though specific cases might find this undesirable, I'm sorry).
 +  $(B This does not apply to prefixes and suffixes).
 +
 +  For every line created from the given `text`, the line prefix defined in the `options` is prefixed onto every newly made line.
 +
 + Peformance:
 +  This function calculates, and reserves all required memory using a single allocation (barring bugs ;3), so it shouldn't
 +  be overly bad to use.
 + ++/
string lineWrap(const(char)[] text, const LineWrapOptions options = LineWrapOptions(120))
{
    import std.exception : assumeUnique, enforce;

    char[] actualText;
    const charsPerLine = options.lineCharLimit - (options.linePrefix.length + + options.lineSuffix.length + 1); // '+ 1' is for the new line char.
    size_t offset      = 0;
    
    enforce(charsPerLine > 0, "The lineCharLimit is too low. There's not enough space for any text (after factoring the prefix, suffix, and ending new line characters).");

    const estimatedLines = (text.length / charsPerLine);
    actualText.reserve(text.length + (options.linePrefix.length * estimatedLines) + (options.lineSuffix.length * estimatedLines));
    
    while(offset < text.length)
    {
        size_t end = (offset + charsPerLine);
        if(end > text.length)
            end = text.length;
        
        // Strip off whitespace, so things format properly.
        while(offset < text.length && text[offset] == ' ')
        {
            offset++;
            if(end < text.length)
                end++;
        }
        
        actualText ~= options.linePrefix;
        actualText ~= text[offset..(end >= text.length) ? text.length : end];
        actualText ~= options.lineSuffix;
        actualText ~= "\n";

        offset += charsPerLine;
    }

    // Don't keep the new line for the last line.
    if(actualText.length > 0 && actualText[$-1] == '\n')
        actualText = actualText[0..$-1];

    return actualText.assumeUnique;
}
///
unittest
{
    const options = LineWrapOptions(8, "\t", "-");
    const text    = "Hello world".lineWrap(options);
    assert(text == "\tHello-\n\tworld-", cast(char[])text);
}

@("issue #2")
unittest
{
    const options = LineWrapOptions(4, "");
    const text    = lineWrap("abcdefgh", options);

    assert(text[$-1] != '\n', "lineWrap is inserting a new line at the end again.");
    assert(text == "abc\ndef\ngh", text);
}

/// Contains a single character, with ANSI styling.
struct TextBufferChar
{
    import jaster.cli.ansi : AnsiColour, AnsiTextFlags, IsBgColour;

    /// foreground
    AnsiColour    fg;
    /// background by reference
    AnsiColour    bgRef;
    /// flags
    AnsiTextFlags flags;
    /// character
    char          value;

    /++
     + Returns:
     +  Whether this character needs an ANSI control code or not.
     + ++/
    @property
    bool usesAnsi() const
    {
        return this.fg    != AnsiColour.init
            || (this.bg   != AnsiColour.init && this.bg != AnsiColour.bgInit)
            || this.flags != AnsiTextFlags.none;
    }

    /// Set the background (automatically sets `value.isBg` to `yes`)
    @property
    void bg(AnsiColour value)
    {
        value.isBg = IsBgColour.yes;
        this.bgRef = value;
    }

    /// Get the background.
    @property
    AnsiColour bg() const { return this.bgRef; }
}

/++
 + A basic rectangle struct, used to specify the bounds of a `TextBufferWriter`.
 + ++/
struct TextBufferBounds
{
    /// x offset
    size_t left;
    /// y offset
    size_t top;
    /// width
    size_t width;
    /// height
    size_t height;

    /// 2D point to 1D array index.
    private size_t pointToIndex(size_t x, size_t y, size_t bufferWidth) const
    {
        return (x + this.left) + (bufferWidth * (y + this.top));
    }
    ///
    unittest
    {
        import std.format : format;
        auto b = TextBufferBounds(0, 0, 5, 5);
        assert(b.pointToIndex(0, 0, 5) == 0);
        assert(b.pointToIndex(0, 1, 5) == 5);
        assert(b.pointToIndex(4, 4, 5) == 24);

        b = TextBufferBounds(1, 1, 3, 2);
        assert(b.pointToIndex(0, 0, 5) == 6);
        assert(b.pointToIndex(1, 0, 5) == 7);
        assert(b.pointToIndex(0, 1, 5) == 11);
        assert(b.pointToIndex(1, 1, 5) == 12);
    }

    private void assertPointInBounds(size_t x, size_t y, size_t bufferWidth, size_t bufferSize) const
    {
        import std.format : format;

        assert(x < this.width,  "X is larger than width. Width = %s, X = %s".format(this.width, x));
        assert(y < this.height, "Y is larger than height. Height = %s, Y = %s".format(this.height, y));

        const maxIndex   = this.pointToIndex(this.width - 1, this.height - 1, bufferWidth);
        const pointIndex = this.pointToIndex(x, y, bufferWidth);
        assert(pointIndex <= maxIndex,  "Index is outside alloted bounds. Max = %s, given = %s".format(maxIndex, pointIndex));
        assert(pointIndex < bufferSize, "Index is outside of the TextBuffer's bounds. Max = %s, given = %s".format(bufferSize, pointIndex));
    }
    ///
    unittest
    {
        // Testing what error messages look like.
        auto b = TextBufferBounds(5, 5, 5, 5);
        //b.assertPointInBounds(6, 0, 0, 0);
        //b.assertPointInBounds(0, 6, 0, 0);
        //b.assertPointInBounds(1, 0, 0, 0);
    }
}

/++
 + A mutable random-access range of `TextBufferChar`s that belongs to a certain bounded area (`TextBufferBound`) within a `TextBuffer`.
 +
 + You can use this range to go over a certain rectangular area of characters using the range API; directly index into this rectangular area,
 + and directly modify elements in this rectangular range.
 +
 + Reading:
 +  Since this is a random-access range, you can either use the normal `foreach`, `popFront` + `front` combo, and you can directly index
 +  into this range.
 +
 +  Note that popping the elements from this range $(B does) affect indexing. So if you `popFront`, then [0] is now what was previous [1], and so on.
 +
 + Writing:
 +  This range implements `opIndexAssign` for both `char` and `TextBufferChar` parameters.
 +
 +  You can either index in a 1D way (using 1 index), or a 2D ways (using 2 indicies, $(B not implemented yet)).
 +
 +  So if you wanted to set the 7th index to a certain character, then you could do `range[6] = '0'`.
 +
 +  You could also do it like so - `range[6] = TextBufferChar(...params here)`
 +
 + See_Also:
 +  `TextBufferWriter.getArea` 
 + ++/
struct TextBufferRange
{
    private
    {
        TextBuffer       _buffer;
        TextBufferBounds _bounds;
        size_t           _cursorX;
        size_t           _cursorY;
        TextBufferChar   _front;

        this(TextBuffer buffer, TextBufferBounds bounds)
        {
            assert(buffer !is null, "Buffer is null.");

            this._buffer = buffer;
            this._bounds = bounds;

            assert(bounds.width > 0,  "Width is 0");
            assert(bounds.height > 0, "Height is 0");
            bounds.assertPointInBounds(bounds.width - 1, bounds.height - 1, buffer._width, buffer._chars.length);

            this.popFront();
        }

        @property
        ref TextBufferChar opIndexImpl(size_t i)
        {
            import std.format : format;
            assert(i < this.length, "Index out of bounds. Length = %s, Index = %s.".format(this.length, i));

            i           += this.progressedLength - 1; // Number's always off by 1.
            const line   = i / this._bounds.width;
            const column = i % this._bounds.width;
            const index  = this._bounds.pointToIndex(column, line, this._buffer._width);

            return this._buffer._chars[index];
        }
    }

    ///
    void popFront()
    {
        if(this._cursorY == this._bounds.height)
        {
            this._buffer = null;
            return;
        }

        const index = this._bounds.pointToIndex(this._cursorX++, this._cursorY, this._buffer._width);
        this._front = this._buffer._chars[index];

        if(this._cursorX >= this._bounds.width)
        {
            this._cursorX = 0;
            this._cursorY++;
        }
    }

    ///
    @property
    TextBufferChar front()
    {
        return this._front;
    }

    ///
    @property
    bool empty() const
    {
        return this._buffer is null;
    }

    /// The bounds that this range are constrained to.
    @property
    TextBufferBounds bounds() const
    {
        return this._bounds;
    }

    /// Effectively how many times `popFront` has been called.
    @property
    size_t progressedLength() const
    {
        return (this._cursorX + (this._cursorY * this._bounds.width));
    }

    /// How many elements are left in the range.
    @property
    size_t length() const
    {
        return (this.empty) ? 0 : ((this._bounds.width * this._bounds.height) - this.progressedLength) + 1; // + 1 is to deal with the staggered empty logic, otherwise this is 1 off constantly.
    }
    alias opDollar = length;

    /// Returns: The character at the specified index.
    @property
    TextBufferChar opIndex(size_t i)
    {
        return this.opIndexImpl(i);
    }

    /++
     + Sets the character value of the `TextBufferChar` at index `i`.
     +
     + Notes:
     +  This preserves the colouring and styling of the `TextBufferChar`, as we're simply changing its value.
     +
     + Params:
     +  ch = The character to use.
     +  i  = The index of the ansi character to change.
     + ++/
    @property
    void opIndexAssign(char ch, size_t i)
    {
        this.opIndexImpl(i).value = ch;
        this._buffer.makeDirty();
    }

    /// ditto.
    @property
    void opIndexAssign(TextBufferChar ch, size_t i)
    {
        this.opIndexImpl(i) = ch;
        this._buffer.makeDirty();
    }
}

/++
 + The main way to modify and read data into/from a `TextBuffer`.
 +
 + Special_Values:
 +  Most of this struct's functions will take an (x, y) position pair, and sometimes
 +  also a (width, height) size pair.
 +
 +  There are some special predefined values that can be used to save yourself some calculations or typing.
 +
 +  For positions these are:
 +      - `TextBuffer.CENTER` to get the center point on whichever axis.
 +      - `TextBuffer.END`    to get the last coordinate on whichever axis.
 +
 +  For sizes these are:
 +      - `TextBuffer.USE_REMAINING_SPACE` to use as much width as possible, taking the starting position into account.
 + ++/
struct TextBufferWriter
{
    import jaster.cli.ansi : AnsiColour, AnsiTextFlags, AnsiText;

    private
    {
        TextBuffer       _buffer;
        TextBufferBounds _bounds;
        AnsiColour       _fg;
        AnsiColour       _bg;
        AnsiTextFlags    _flags;

        this(TextBuffer buffer, TextBufferBounds bounds)
        {
            this._buffer = buffer;
            this._bounds = bounds;
        }

        void setSingleChar(size_t index, char ch, AnsiColour fg, AnsiColour bg, AnsiTextFlags flags)
        {
            scope value = &this._buffer._chars[index];
            value.value = ch;
            value.fg    = fg;
            value.bg    = bg;
            value.flags = flags;
        }

        void fixSize(ref size_t size, const size_t offset, const size_t maxSize)
        {
            if(size == TextBuffer.USE_REMAINING_SPACE)
                size = maxSize - offset;
        }

        void fixAxis(ref size_t axis, const size_t axisSizeInclusive)
        {
            if(axis == TextBuffer.CENTER)
                axis = (axisSizeInclusive - 1) / 2; // - 1 to make it exclusive, because 0-based logic.
            else if(axis == TextBuffer.END)
                axis = (axisSizeInclusive - 1);
        }
    }

    /++
     + Sets a character at a specific point.
     +
     + Assertions:
     +  The point (x, y) must be in bounds.
     +
     + Params:
     +  x  = The x position of the point.
     +  y  = The y position of the point.
     +  ch = The character to place.
     +
     + Returns:
     +  `this`, for function chaining.
     + ++/
    TextBufferWriter set(size_t x, size_t y, char ch)
    {
        this.fixAxis(/*ref*/ x, this.bounds.width);
        this.fixAxis(/*ref*/ y, this.bounds.height);

        const index = this._bounds.pointToIndex(x, y, this._buffer._width);
        this._bounds.assertPointInBounds(x, y, this._buffer._width, this._buffer._chars.length);

        this.setSingleChar(index, ch, this._fg, this._bg, this._flags);
        this._buffer.makeDirty();

        return this;
    }

    /++
     + Fills an area with a specific character.
     +
     + Assertions:
     +  The point (x, y) must be in bounds.
     +
     + Params:
     +  x      = The starting x position.
     +  y      = The starting y position.
     +  width  = How many characters to fill.
     +  height = How many lines to fill.
     +  ch     = The character to place.
     +
     + Returns:
     +  `this`, for function chaining.
     + ++/
    TextBufferWriter fill(size_t x, size_t y, size_t width, size_t height, char ch)
    {
        this.fixAxis(/*ref*/ x, this.bounds.width);
        this.fixAxis(/*ref*/ y, this.bounds.height);
        this.fixSize(/*ref*/ width, x, this.bounds.width);
        this.fixSize(/*ref*/ height, y, this.bounds.height);

        const bufferLength = this._buffer._chars.length;
        const bufferWidth  = this._buffer._width;
        foreach(line; 0..height)
        {
            foreach(column; 0..width)
            {
                // OPTIMISATION: We should be able to fill each line in batch, rather than one character at a time.
                const newX  = x + column;
                const newY  = y + line;
                const index = this._bounds.pointToIndex(newX, newY, bufferWidth);
                this._bounds.assertPointInBounds(newX, newY, bufferWidth, bufferLength);
                this.setSingleChar(index, ch, this._fg, this._bg, this._flags);
            }
        }

        this._buffer.makeDirty();
        return this;
    }

    /++
     + Writes some text starting at the given point.
     +
     + Notes:
     +  If there's too much text to write, it'll simply be left out.
     +
     +  Text will automatically overflow onto the next line down, starting at the given `x` position on each new line.
     +
     +  New line characters are handled properly.
     +
     +  When text overflows onto the next line, any spaces before the next visible character are removed.
     +
     +  ANSI text is $(B only) supported by the overload of this function that takes an `AnsiText` instead of a `char[]`.
     +
     + Params:
     +  x    = The starting x position.
     +  y    = The starting y position.
     +  text = The text to write.
     +
     + Returns:
     +  `this`, for function chaining.
     + +/
    TextBufferWriter write(size_t x, size_t y, const char[] text)
    {
        this.fixAxis(/*ref*/ x, this.bounds.width);
        this.fixAxis(/*ref*/ y, this.bounds.height);

        const width  = this.bounds.width - x;
        const height = this.bounds.height - y;
        
        const bufferLength = this._buffer._chars.length;
        const bufferWidth  = this._buffer._width;
        this.bounds.assertPointInBounds(x,               y,                bufferWidth, bufferLength);
        this.bounds.assertPointInBounds(x + (width - 1), y + (height - 1), bufferWidth, bufferLength); // - 1 to make the width and height exclusive.

        auto cursorX = x;
        auto cursorY = y;

        void nextLine(ref size_t i)
        {
            cursorX = x;
            cursorY++;

            // Eat any spaces, similar to how lineWrap functions.
            // TODO: I think I should make a lineWrap range for situations like this, where I specifically won't use lineWrap due to allocations.
            //       And then I can just make the original lineWrap function call std.range.array on the range.
            while(i < text.length - 1 && text[i + 1] == ' ')
                i++;
        }
        
        for(size_t i = 0; i < text.length; i++)
        {
            const ch = text[i];
            if(ch == '\n')
            {
                nextLine(i);

                if(cursorY >= height)
                    break;
            }

            const index = this.bounds.pointToIndex(cursorX, cursorY, bufferWidth);
            this.setSingleChar(index, ch, this._fg, this._bg, this._flags);

            cursorX++;
            if(cursorX == x + width)
            {
                nextLine(i);

                if(cursorY >= height)
                    break;
            }
        }

        this._buffer.makeDirty();
        return this;
    }

    /// ditto.
    TextBufferWriter write(size_t x, size_t y, AnsiText text)
    {
        const fg    = this.fg;
        const bg    = this.bg;
        const flags = this.flags;

        this.fg    = text.getFg(); // TODO: These names need to become consistant.
        this.bg    = text.getBg();
        this.flags = text.flags();

        this.write(x, y, text.rawText); // Can only fail asserts, never exceptions, so we don't need scope(exit/failure).

        this.fg    = fg;
        this.bg    = bg;
        this.flags = flags;
        return this;
    }

    /++
     + Assertions:
     +  The point (x, y) must be in bounds.
     +
     + Params:
     +  x = The x position.
     +  y = The y position.
     +
     + Returns:
     +  The `TextBufferChar` at the given point (x, y)
     + ++/
    TextBufferChar get(size_t x, size_t y)
    {
        this.fixAxis(/*ref*/ x, this.bounds.width);
        this.fixAxis(/*ref*/ y, this.bounds.height);

        const index = this._bounds.pointToIndex(x, y, this._buffer._width);
        this._bounds.assertPointInBounds(x, y, this._buffer._width, this._buffer._chars.length);

        return this._buffer._chars[index];
    }

    /++
     + Returns a mutable, random-access (indexable) range (`TextBufferRange`) containing the characters
     + of the specified area.
     +
     + Params:
     +  x      = The x position to start at.
     +  y      = The y position to start at.
     +  width  = How many characters per line.
     +  height = How many lines.
     +
     + Returns:
     +  A `TextBufferRange` that is configured for the given area.
     + ++/
    TextBufferRange getArea(size_t x, size_t y, size_t width, size_t height)
    {
        this.fixAxis(x, this.bounds.width);
        this.fixAxis(y, this.bounds.height);

        auto bounds = TextBufferBounds(this._bounds.left + x, this._bounds.top + y);
        this.fixSize(/*ref*/ width,  bounds.left, this.bounds.width);
        this.fixSize(/*ref*/ height, bounds.top,  this.bounds.height);

        bounds.width  = width;
        bounds.height = height;

        return TextBufferRange(this._buffer, bounds);
    }

    /// The bounds that this `TextWriter` is constrained to.
    @property
    TextBufferBounds bounds() const
    {
        return this._bounds;
    }
    
    /// Set the foreground for any newly-written characters.
    /// Returns: `this`, for function chaining.
    @property
    TextBufferWriter fg(AnsiColour fg) { this._fg = fg; return this; }
    /// Set the background for any newly-written characters.
    /// Returns: `this`, for function chaining.
    @property
    TextBufferWriter bg(AnsiColour bg) { this._bg = bg; return this; }
    /// Set the flags for any newly-written characters.
    /// Returns: `this`, for function chaining.
    @property
    TextBufferWriter flags(AnsiTextFlags flags) { this._flags = flags; return this; }

    /// Get the foreground.
    @property
    AnsiColour fg() { return this._fg; }
    /// Get the foreground.
    @property
    AnsiColour bg() { return this._bg; }
    /// Get the foreground.
    @property
    AnsiTextFlags flags() { return this._flags; }
}
///
unittest
{
    import std.format : format;
    import jaster.cli.ansi;

    auto buffer         = new TextBuffer(5, 4);
    auto writer         = buffer.createWriter(1, 1, 3, 2); // Offset X, Offset Y, Width, Height.
    auto fullGridWriter = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    // Clear grid to be just spaces.
    fullGridWriter.fill(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE, ' ');

    // Write some stuff in the center.
    with(writer)
    {
        set(0, 0, 'A');
        set(1, 0, 'B');
        set(2, 0, 'C');

        fg = AnsiColour(Ansi4BitColour.green);

        set(0, 1, 'D');
        set(1, 1, 'E');
        set(2, 1, 'F');
    }

    assert(buffer.toStringNoDupe() == 
        "     "
       ~" ABC "
       ~" \033[32mDEF\033[0m " // \033 stuff is of course, the ANSI codes. In this case, green foreground, as we set above.
       ~"     ",

       buffer.toStringNoDupe() ~ "\n%s".format(cast(ubyte[])buffer.toStringNoDupe())
    );

    assert(writer.get(1, 1) == TextBufferChar(AnsiColour(Ansi4BitColour.green), AnsiColour.bgInit, AnsiTextFlags.none, 'E'));
}

@("Testing that basic operations work")
unittest
{
    import std.format : format;

    auto buffer = new TextBuffer(3, 3);
    auto writer = buffer.createWriter(1, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    foreach(ref ch; buffer._chars)
        ch.value = '0';

    writer.set(0, 0, 'A');
    writer.set(1, 0, 'B');
    writer.set(0, 1, 'C');
    writer.set(1, 1, 'D');
    writer.set(1, 2, 'E');

    assert(buffer.toStringNoDupe() == 
         "0AB"
        ~"0CD"
        ~"00E"
    , "%s".format(buffer.toStringNoDupe()));
}

@("Testing that ANSI works (but only when the entire thing is a single ANSI command)")
unittest
{
    import std.format : format;
    import jaster.cli.ansi : AnsiText, Ansi4BitColour, AnsiColour;

    auto buffer = new TextBuffer(3, 1);
    auto writer = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    writer.fg = AnsiColour(Ansi4BitColour.green);
    writer.set(0, 0, 'A');
    writer.set(1, 0, 'B');
    writer.set(2, 0, 'C');

    assert(buffer.toStringNoDupe() == 
         "\033[%smABC%s".format(cast(int)Ansi4BitColour.green, AnsiText.RESET_COMMAND)
    , "%s".format(buffer.toStringNoDupe()));
}

@("Testing that a mix of ANSI and plain text works")
unittest
{
    import std.format : format;
    import jaster.cli.ansi : AnsiText, Ansi4BitColour, AnsiColour;

    auto buffer = new TextBuffer(3, 4);
    auto writer = buffer.createWriter(0, 1, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    buffer.createWriter(0, 0, 3, 1).fill(0, 0, 3, 1, ' '); // So we can also test that the y-offset works.

    writer.fg = AnsiColour(Ansi4BitColour.green);
    writer.set(0, 0, 'A');
    writer.set(1, 0, 'B');
    writer.set(2, 0, 'C');
    
    writer.fg = AnsiColour.init;
    writer.set(0, 1, 'D');
    writer.set(1, 1, 'E');
    writer.set(2, 1, 'F');

    writer.fg = AnsiColour(Ansi4BitColour.green);
    writer.set(0, 2, 'G');
    writer.set(1, 2, 'H');
    writer.set(2, 2, 'I');

    assert(buffer.toStringNoDupe() == 
         "   "
        ~"\033[%smABC%s".format(cast(int)Ansi4BitColour.green, AnsiText.RESET_COMMAND)
        ~"DEF"
        ~"\033[%smGHI%s".format(cast(int)Ansi4BitColour.green, AnsiText.RESET_COMMAND)
    , "%s".format(buffer.toStringNoDupe()));
}

@("Various fill tests")
unittest
{
    auto buffer = new TextBuffer(5, 4);
    auto writer = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    writer.fill(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE, ' '); // Entire grid fill
    auto spaces = new char[buffer._chars.length];
    spaces[] = ' ';
    assert(buffer.toStringNoDupe() == spaces);

    writer.fill(0, 0, TextBuffer.USE_REMAINING_SPACE, 1, 'A'); // Entire line fill
    assert(buffer.toStringNoDupe()[0..5] == "AAAAA");

    writer.fill(1, 1, TextBuffer.USE_REMAINING_SPACE, 1, 'B'); // Partial line fill with X-offset and automatic width.
    assert(buffer.toStringNoDupe()[5..10] == " BBBB", buffer.toStringNoDupe()[5..10]);

    writer.fill(1, 2, 3, 2, 'C'); // Partial line fill, across multiple lines.
    assert(buffer.toStringNoDupe()[10..20] == " CCC  CCC ");
}

@("Issue with TextBufferRange length")
unittest
{
    import std.range : walkLength;

    auto buffer = new TextBuffer(3, 2);
    auto writer = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);
    auto range  = writer.getArea(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    foreach(i; 0..6)
    {
        assert(!range.empty);
        assert(range.length == 6 - i);
        range.popFront();
    }
    assert(range.empty);
    assert(range.length == 0);
}

@("Test TextBufferRange")
unittest
{
    import std.algorithm   : equal;
    import std.format      : format;
    import std.range       : walkLength;
    import jaster.cli.ansi : AnsiColour, AnsiTextFlags;

    auto buffer = new TextBuffer(3, 2);
    auto writer = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    with(writer)
    {
        set(0, 0, 'A');
        set(1, 0, 'B');
        set(2, 0, 'C');
        set(0, 1, 'D');
        set(1, 1, 'E');
        set(2, 1, 'F');
    }
    
    auto range = writer.getArea(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);
    assert(range.walkLength == buffer.toStringNoDupe().length, "%s != %s".format(range.walkLength, buffer.toStringNoDupe().length));
    assert(range.equal!"a.value == b"(buffer.toStringNoDupe()));

    range = writer.getArea(1, 1, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);
    assert(range.walkLength == 2);

    range = writer.getArea(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);
    range[0] = '1';
    range[1] = '2';
    range[2] = '3';

    foreach(i; 0..3)
        range.popFront();

    // Since the range has been popped, the indicies have moved forward.
    range[1] = TextBufferChar(AnsiColour.init, AnsiColour.init, AnsiTextFlags.none, '4');

    assert(buffer.toStringNoDupe() == "123D4F", buffer.toStringNoDupe());
}

@("Test write")
unittest
{
    import std.format      : format;    
    import jaster.cli.ansi : AnsiColour, AnsiTextFlags, ansi, Ansi4BitColour;

    auto buffer = new TextBuffer(6, 4);
    auto writer = buffer.createWriter(1, 1, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE)
          .fill(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE, ' ');
    writer.write(0, 0, "Hello World!");

    assert(buffer.toStringNoDupe() ==
        "      "
       ~" Hello"
       ~" World"
       ~" !    ",
       buffer.toStringNoDupe()
    );

    writer.write(1, 2, "Pog".ansi.fg(Ansi4BitColour.green));
    assert(buffer.toStringNoDupe() ==
        "      "
       ~" Hello"
       ~" World"
       ~" !\033[32mPog\033[0m ",
       buffer.toStringNoDupe()
    );
}

@("Test addNewLine mode")
unittest
{
    import jaster.cli.ansi : AnsiColour, Ansi4BitColour;

    auto buffer = new TextBuffer(3, 3, TextBufferOptions(TextBufferLineMode.addNewLine));
    auto writer = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    writer.write(0, 0, "ABC DEF GHI");
    assert(buffer.toStringNoDupe() ==
        "ABC\n"
       ~"DEF\n"
       ~"GHI"
    );

    writer.fg = AnsiColour(Ansi4BitColour.green);
    writer.write(0, 0, "ABC DEF GHI");
    assert(buffer.toStringNoDupe() ==
        "\033[32mABC\n"
       ~"DEF\n"
       ~"GHI\033[0m"
    );
}

@("Test CENTER")
unittest
{
    auto buffer = new TextBuffer(11, 1);
    auto writer = buffer.createWriter(0, 0, TextBuffer.USE_REMAINING_SPACE, TextBuffer.USE_REMAINING_SPACE);

    writer.fill(0, 0, 11, 1, ' ')
          .set(TextBuffer.CENTER, 0, 'A');
    assert(buffer.toStringNoDupe() == "     A     ", '"'~buffer.toStringNoDupe()~'"');

    writer.fill(TextBuffer.CENTER, 0, 3, 1, 'B');
    assert(buffer.toStringNoDupe() == "     BBB   ");

    writer.write(TextBuffer.CENTER, 0, "Lol");
    assert(buffer.toStringNoDupe() == "     Lol   ");
}

@("Test END")
unittest
{
    auto buffer = new TextBuffer(2, 1);
    auto writer = buffer.createWriter(0, 0, 2, 1);

    writer.fill(0, 0, 2, 1, ' ')
          .set(TextBuffer.END, 0, 'A');
    assert(buffer.toStringNoDupe() == " A");
}

/++
 + Determines how a `TextBuffer` handles writing out each of its internal "lines".
 + ++/
enum TextBufferLineMode
{
    /// Each "line" inside of the `TextBuffer` is written sequentially, without any non-explicit new lines between them.
    sideBySide,

    /// Each "line" inside of the `TextBuffer` is written sequentially, with an automatically inserted new line between them.
    /// Note that the inserted new line doesn't count towards the character limit for each line.
    addNewLine
}

/++
 + Options for a `TextBuffer`
 + ++/
struct TextBufferOptions
{
    /// Determines how a `TextBuffer` writes each of its "lines".
    TextBufferLineMode lineMode = TextBufferLineMode.sideBySide;
}

// I want reference semantics.
/++
 + An ANSI-enabled class used to easily manipulate a text buffer of a fixed width and height.
 +
 + Description:
 +  This class was inspired by the GPU component from the OpenComputers Minecraft mod.
 +
 +  I thought having something like this, where you can easily manipulate a 2D grid of characters (including colour and the like)
 +  would be quite valuable.
 +
 +  For example, the existance of this class can be the stepping stone into various other things such as: a basic (and I mean basic) console-based UI functionality;
 +  other ANSI-enabled components such as tables which can otherwise be a pain due to the non-uniform length of ANSI text (e.g. ANSI codes being invisible characters),
 +  and so on.
 +
 + Examples:
 +  For now you'll have to explore the source (text.d) and have a look at the module-level unittests to see some testing examples.
 +
 +  When I can be bothered, I'll add user-facing examples :)
 +
 + Limitations:
 +  Currently the buffer must be given a fixed size, but I'm hoping to fix this (at the very least for the y-axis) in the future.
 +  It's probably pretty easy, I just haven't looked into doing it yet.
 +
 +  Creating the final string output (via `toString` or `toStringNoDupe`) is unoptimised. It performs pretty well for a 180x180 buffer with a sparing amount of colours,
 +  but don't expect it to perform too well right now.
 +  One big issue is that *any* change will cause the entire output to be reconstructed, which I'm sure can be changed to be a bit more optimal.
 + ++/
final class TextBuffer
{
    // The extra enums logically shouldn't be here, but from a UX having them all in on place is beneficial.

    /// Used to specify that a writer's width or height should use all the space it can.
    enum USE_REMAINING_SPACE = size_t.max;

    /// Used to specify that an X or Y position should be the center point of an area.
    enum CENTER = size_t.max - 1;

    /// Used to specify that an X or Y position should be at the end of its axis.
    enum END    = size_t.max - 2;

    private
    {
        TextBufferChar[] _chars;
        size_t           _width;
        size_t           _height;

        char[] _output;
        char[] _cachedOutput;

        TextBufferOptions _options;

        void makeDirty()
        {
            this._cachedOutput = null;
        }
    }

    /++
     + Creates a new `TextBuffer` with the specified width and height.
     +
     + Params:
     +  width   = How many characters each line can contain.
     +  height  = How many lines in total there are.
     +  options = Configuration options for this `TextBuffer`.
     + ++/
    this(size_t width, size_t height, TextBufferOptions options = TextBufferOptions.init)
    {
        this._width        = width;
        this._height       = height;
        this._chars.length = width * height;
        this._options      = options;
    }
    
    /++
     + Creates a new `TextBufferWriter` bound to this `TextBuffer`.
     +
     + Description:
     +  The only way to read and write to certain sections of a `TextBuffer` is via the `TextBufferWriter`.
     +
     +  Writers are constrained to the given `bounds`, allowing careful control of where certain parts of your code are allowed to modify.
     +
     + Params:
     +  bounds = The bounds to constrain the writer to.
     +           You can use `TextBuffer.USE_REMAINING_SPACE` as the width and height to specify that the writer's width/height will use
     +           all the space that they have available.
     +
     + Returns:
     +  A `TextBufferWriter`, constrained to the given `bounds`, which is also bounded to this specific `TextBuffer`.
     + ++/
    TextBufferWriter createWriter(TextBufferBounds bounds)
    {
        if(bounds.width == USE_REMAINING_SPACE)
            bounds.width = this._width - bounds.left;

        if(bounds.height == USE_REMAINING_SPACE)
            bounds.height = this._height - bounds.top;

        return TextBufferWriter(this, bounds);
    }

    /// ditto.
    TextBufferWriter createWriter(size_t left, size_t top, size_t width, size_t height)
    {
        return this.createWriter(TextBufferBounds(left, top, width, height));
    }

    // This is a very slow (well, I assume, tired code is usually slow code), very naive function, but as long as it works for now, then it can be rewritten later.
    /++
     + Converts this `TextBuffer` into a string.
     +
     + Description:
     +  The value returned by this function is a slice into an internal buffer. This buffer gets
     +  reused between every call to this function.
     +
     +  So basically, if you don't need the guarentees of `immutable` (which `toString` will provide), and are aware
     +  that the value from this function can and will change, then it is faster to use this function as otherwise, with `toString`,
     +  a call to `.idup` is made.
     +
     + Optimisation:
     +  This function isn't terribly well optimised in all honesty, but that isn't really too bad of an issue because, at least on
     +  my computer, it only takes around 2ms to create the output for a 180x180 grid, in the worst case scenario - where every character
     +  requires a different ANSI code.
     +
     +  Worst case is O(3n), best case is O(2n), backtracking only occurs whenever a character is found that cannot be written with the same ANSI codes
     +  as the previous one(s), so the worst case only occurs if every single character requires a new ANSI code.
     +
     +  Small test output - `[WORST CASE | SHARED] ran 1000 times -> 1 sec, 817 ms, 409 us, and 5 hnsecs -> AVERAGING -> 1 ms, 817 us, and 4 hnsecs`
     +
     +  While I haven't tested memory usage, by default all of the initial allocations will be `(width * height) * 2`, which is then reused between runs.
     +
     +  This function will initially set the internal buffer to `width * height * 2` in an attempt to overallocate more than it needs.
     +
     +  This function caches its output (using the same buffer), and will reuse the cached output as long as there hasn't been any changes.
     +
     +  If there *have* been changes, then the internal buffer is simply reused without clearing or reallocation.
     +
     +  Finally, this function will automatically group together ranges of characters that can be used with the same ANSI codes, as an
     +  attempt to minimise the amount of characters actually required. So the more characters in a row there are that are the same colour and style,
     +  the faster this function performs.
     +
     + Returns:
     +  An (internally mutable) slice to this class' output buffer.
     + ++/
    const(char[]) toStringNoDupe()
    {
        import std.algorithm   : joiner;
        import std.utf         : byChar;
        import jaster.cli.ansi : AnsiComponents, populateActiveAnsiComponents, AnsiText;

        if(this._output is null)
            this._output = new char[this._chars.length * 2]; // Optimistic overallocation, to lower amount of resizes

        if(this._cachedOutput !is null)
            return this._cachedOutput;

        size_t outputCursor;
        size_t ansiCharCursor;
        size_t nonAnsiCount;

        // Auto-increments outputCursor while auto-resizing the output buffer.
        void putChar(char c, bool isAnsiChar)
        {
            if(!isAnsiChar)
                nonAnsiCount++;

            if(outputCursor >= this._output.length)
                this._output.length *= 2;

            this._output[outputCursor++] = c;

            // Add new lines if the option is enabled.
            if(!isAnsiChar
            && this._options.lineMode == TextBufferLineMode.addNewLine
            && nonAnsiCount           == this._width)
            {
                this._output[outputCursor++] = '\n';
                nonAnsiCount = 0;
            }
        }
        
        // Finds the next sequence of characters that have the same foreground, background, and flags.
        // e.g. the next sequence of characters that can be used with the same ANSI command.
        // Returns `null` once we reach the end.
        TextBufferChar[] getNextAnsiRange()
        {
            if(ansiCharCursor >= this._chars.length)
                return null;

            const startCursor = ansiCharCursor;
            const start       = this._chars[ansiCharCursor++];
            while(ansiCharCursor < this._chars.length)
            {
                auto current  = this._chars[ansiCharCursor++];
                current.value = start.value; // cheeky way to test equality.
                if(start != current)
                {
                    ansiCharCursor--;
                    break;
                }
            }

            return this._chars[startCursor..ansiCharCursor];
        }

        auto sequence = getNextAnsiRange();
        while(sequence.length > 0)
        {
            const first = sequence[0]; // Get the first character so we can get the ANSI settings for the entire sequence.
            if(first.usesAnsi)
            {
                AnsiComponents components;
                const activeCount = components.populateActiveAnsiComponents(first.fg, first.bg, first.flags);

                putChar('\033', true);
                putChar('[', true);
                foreach(ch; components[0..activeCount].joiner(";").byChar)
                    putChar(ch, true);
                putChar('m', true);
            }

            foreach(ansiChar; sequence)
                putChar(ansiChar.value, false);

            // Remove final new line, since it's more expected for it not to be there.
            if(this._options.lineMode         == TextBufferLineMode.addNewLine
            && ansiCharCursor                 >= this._chars.length
            && this._output[outputCursor - 1] == '\n')
                outputCursor--; // For non ANSI, we just leave the \n orphaned, for ANSI, we just overwrite it with the reset command below.

            if(first.usesAnsi)
            {
                foreach(ch; AnsiText.RESET_COMMAND)
                    putChar(ch, true);
            }

            sequence = getNextAnsiRange();
        }

        this._cachedOutput = this._output[0..outputCursor];
        return this._cachedOutput;
    }

    /// Returns: `toStringNoDupe`, but then `.idup`s the result.
    override string toString()
    {
        return this.toStringNoDupe().idup;
    }
}