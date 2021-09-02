module jcli.cli;

import jcli, std;

final class CommandLineInterface(Modules...)
{
    alias ArgBinderInstance = ArgBinder!Modules;

    private alias CommandExecute = int delegate(ArgParser);
    private alias CommandHelp    = string delegate();

    private struct CommandInfo
    {
        CommandExecute onExecute;
        CommandHelp onHelp;
        Pattern pattern;
        string description;
    }

    private
    {
        Resolver!CommandInfo _resolver;
        CommandInfo[] _uniqueCommands;
        CommandInfo _default;
        string _appName;
    }

    this()
    {
        this._resolver = new typeof(_resolver)();
        static foreach(mod; Modules)
            this.findCommands!mod;
        this._appName = thisExePath().baseName;
    }

    int parseAndExecute(string[] args, bool ignoreFirstArg = true)
    {
        return this.parseAndExecute(ArgParser(ignoreFirstArg ? args[1..$] : args));
    }

    int parseAndExecute(ArgParser parser)
    {
        auto parserCopy = parser;
        if(parser.empty)
            parser = ArgParser(["-h"]);

        string[] args;
        auto command = this.resolveCommand(parser, args);
        if(command.kind == command.Kind.partial || command == typeof(command).init)
        {
            if(this._default == CommandInfo.init)
            {
                HelpText help = HelpText.make(180);
                
                if(parserCopy.empty || parserCopy == ArgParser(["-h"]))
                    help.addHeader("Available commands:");
                else
                {
                    help.addLineWithPrefix(this._appName~": ", "Unknown command", AnsiStyleSet.init.fg(Ansi4BitColour.red));
                    help.addLine(null);
                    help.addHeader("Did you mean:");
                }
                foreach(comm; this._uniqueCommands)
                    help.addArgument(comm.pattern.patterns.front, [HelpTextDescription(0, comm.description)]);
                writeln(help.finish());
                return -1;
            }
            else
            {
                if(this.hasHelpArgument(parser) && !parserCopy.empty)
                {
                    writeln(this._default.onHelp());
                    return 0;
                }

                try return this._default.onExecute(parserCopy);
                catch(Exception ex)
                {
                    writefln("%s: %s", this._appName.ansi.fg(Ansi4BitColour.red), ex.msg);
                    debug writeln(ex);
                    return -1;
                }
            }
        }

        if(this.hasHelpArgument(parser))
        {
            writeln(command.fullMatchChain[$-1].userData.onHelp());
            return 0;
        }
        else if(args.length && args[$-1] == "--__jcli:complete")
        {
            args = args[0..$-1];

            if(command.valueProvider)
                writeln(command.valueProvider(args));
            else
                writeln("Command does not contain a value provider.");
            return 0;
        }

        try return command.fullMatchChain[$-1].userData.onExecute(parser);
        catch(Exception ex)
        {
            writefln("%s: %s", this._appName.ansi.fg(Ansi4BitColour.red), ex.msg);
            debug writeln("[debug-only] JCLI has displayed this exception in full for your convenience.");
            debug writeln(ex);
            return -1;
        }
    }

    ResolveResult!CommandInfo resolveCommand(ref ArgParser parser, out string[] args)
    {
        typeof(return) lastPartial;

        string[] command;
        scope(exit)
            args = parser.map!(r => r.fullSlice).array;

        while(true)
        {
            if(parser.empty)
                return lastPartial;
            if(parser.front.kind == ArgParser.Result.Kind.argument)
                return lastPartial;

            command ~= parser.front.fullSlice;
            auto result = this._resolver.resolve(command);

            if(result.kind == result.Kind.partial)
                lastPartial = result;
            else
            {
                parser.popFront();
                return result;
            }

            parser.popFront();
        }
    }

    private bool hasHelpArgument(ArgParser parser)
    {
        return parser
                .filter!(r => r.kind == r.Kind.argument)
                .any!(r => r.nameSlice == "h" || r.nameSlice == "help");
    }

    private void findCommands(alias Module)()
    {
        static foreach(member; __traits(allMembers, Module))
        {{
            alias Symbol = __traits(getMember, Module, member);
            static if(hasUDA!(Symbol, Command) || hasUDA!(Symbol, CommandDefault))
                this.getCommand!Symbol;
        }}
    }

    private void getCommand(alias CommandT)()
    {
        CommandInfo info;

        info.onHelp = getOnHelp!CommandT();
        info.onExecute = getOnExecute!CommandT();

        static if(hasUDA!(CommandT, Command))
        {
            info.pattern = getUDAs!(CommandT, Command)[0].pattern;
            info.description = getUDAs!(CommandT, Command)[0].description;
            foreach(pattern; info.pattern.patterns)
                this._resolver.add(pattern.splitter(' ').array, info, &(AutoComplete!CommandT()).complete);
            this._uniqueCommands ~= info;
        }
        else
            this._default = info;
    }

    private CommandExecute getOnExecute(alias CommandT)()
    {
        return (ArgParser parser) 
        {
            auto comParser = CommandParser!(CommandT, ArgBinderInstance)();
            auto result = comParser.parse(parser);
            enforce(result.isOk, result.error);

            auto com = result.value;
            static if(is(typeof(com.onExecute()) == int))
                return com.onExecute();
            else
            {
                com.onExecute();
                return 0;
            }
        };
    }

    private CommandHelp getOnHelp(alias CommandT)()
    {
        return ()
        {
            return CommandHelpText!CommandT().generate();
        };
    }
}

version(unittest)
@Command("assert even|ae|a e", "Asserts that the given number is even.")
private struct AssertEvenCommand
{
    @ArgPositional("number", "The number to assert.")
    int number;

    @ArgNamed("reverse|r", "If specified, then assert that the number is ODD instead.")
    Nullable!bool reverse;

    int onExecute()
    {
        auto passedAssert = (this.reverse.get(false))
                            ? this.number % 2 == 1
                            : this.number % 2 == 0;

        return (passedAssert) ? 0 : 128;
    }
}

version(unittest)
@CommandDefault("echo")
private struct EchoCommand
{
    @ArgOverflow
    string[] overflow;

    int onExecute()
    {
        foreach(value; overflow)
            writeln(value);
        return 69;
    }
}

unittest
{
    auto cli = new CommandLineInterface!(jcli.cli);
    auto p = ArgParser(["a"]);
    string[] a;
    auto r = cli.resolveCommand(p, a);
    assert(r.kind == r.Kind.partial);
    assert(r.fullMatchChain.length == 1);
    assert(r.fullMatchChain[0].fullMatchString == "a");
    assert(r.partialMatches.length == 2);
    assert(r.partialMatches[0].fullMatchString == "assert");
    assert(r.partialMatches[1].fullMatchString == "ae");

    foreach(args; [["ae", "2"], ["assert", "even", "2"], ["a", "e", "2"]])
    {
        p = ArgParser(args);
        r = cli.resolveCommand(p, a);
        assert(r.kind == r.Kind.full);
        assert(r.fullMatchChain.length == args.length-1);
        assert(r.fullMatchChain.map!(fm => fm.fullMatchString).equal(args[0..$-1]));
        assert(p.front.fullSlice == "2", p.to!string);
        assert(r.fullMatchChain[$-1].userData.onExecute(p) == 0);
    }

    foreach(args; [["ae", "1", "--reverse"], ["a", "e", "-r", "1"]])
    {
        p = ArgParser(args);
        r = cli.resolveCommand(p, a);
        assert(r.kind == r.Kind.full);
        assert(r.fullMatchChain[$-1].userData.onExecute(p) == 0);
    }

    assert(cli.parseAndExecute(["assert", "even", "2"], false) == 0);
    assert(cli.parseAndExecute(["assert", "even", "1", "-r"], false) == 0);
    assert(cli.parseAndExecute(["assert", "even", "2", "-r"], false) == 128);
    assert(cli.parseAndExecute(["assert", "even", "1"], false) == 128);

    // Commented out to stop it from writing output.
    // assert(cli.parseAndExecute(["assrt", "evn", "20"], false) == 69);
}