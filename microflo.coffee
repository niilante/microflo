# MicroFlo - Flow-Based Programming for microcontrollers
# Copyright (c) 2013 Jon Nordby <jononor@gmail.com>
# MicroFlo may be freely distributed under the MIT license

require "coffee-script/register"
fs = require("fs")
path = require("path")
cmdFormat = require("./microflo/commandformat.json")
microflo = require("./lib/microflo")
commander = require("commander")
pkginfo = require("pkginfo")(module)

defaultLibrary = 'microflo-core/components/arduino-standard.json'

setupRuntimeCommand = (env) ->
    serialPortToUse = env.serial or "auto"
    port = env.port or 3569
    debugLevel = env.debug or "Error"
    ip = env.ip or "127.0.0.1"
    baud = parseInt(env.baudrate) or 9600
    componentMap = env.componentmap
    if env.file
        file = path.resolve env.file
        microflo.runtime.setupSimulator file, baud, port, debugLevel, ip, (err, runtime) ->
            throw err if err
    else
        microflo.runtime.setupRuntime serialPortToUse, baud, port, debugLevel, ip, componentMap, (err, runtime) ->
            throw err  if err


uploadGraphCommand = (graphPath, env) ->
  microflo.runtime.uploadGraphFromFile graphPath, env, (err) ->
    if err
      console.error err
      console.error err.stack if err.stack
      process.exit 1
    console.log 'Graph uploaded and running'
    process.exit 0

generateFwCommand = (inputFile, outputDir, env) ->

    target = env.target or "arduino"
    outputFile = outputDir + "/main.cpp"
    library = env.library or defaultLibrary
    componentLib = new microflo.componentlib.ComponentLibrary()
    componentLib.loadSetFile library, (err) ->
        throw err  if err
        componentLib.loadFile inputFile
        microflo.generate.updateComponentLibDefinitions componentLib, outputDir, "createComponent"
        microflo.generate.generateOutput componentLib, inputFile, outputFile, target


registerRuntimeCommand = (user, env) ->
    ip = env.ip or "auto"
    port = parseInt(env.port) or 3569
    label = env.label or "MicroFlo"
    id = env.id or process.env["MICROFLO_RUNTIME_ID"]
    user = process.env["FLOWHUB_USER_ID"]  unless user
    rt = microflo.runtime.createFlowhubRuntime(user, ip, port, label)
    unless id
        microflo.runtime.registerFlowhubRuntime rt, (err, ok) ->
        if err
            console.log "Could not register runtime with Flowhub", err
            process.exit 1
        else
            console.log "Runtime registered with id:", rt.runtime.id


generateComponentLib = (componentlibJsonFile, componentlibOutputPath, factoryMethodName, env) ->
    componentLibraryDefinition = undefined
    componentLibrary = undefined

    # load specified component library Json definition
    componentLibraryDefinition = require(componentlibJsonFile)
    componentLibrary = new microflo.componentlib.ComponentLibrary(componentLibraryDefinition, componentlibOutputPath)
    componentLibrary.load()

    # write component library definitions to external source or inside microflo project
    microflo.generate.updateComponentLibDefinitions componentLibrary, componentlibOutputPath, factoryMethodName

flashCommand = (file, env) ->
    upload = require("./lib/flash.coffee")
    tty = env.serial
    baud = parseInt(env.baudrate) or 115200
    upload.avrUploadHexFile file, tty, baud, (err, written) ->
        console.log err, written

updateDefsCommand = (directory) ->
    microflo.generate.updateDefinitions directory

generateFactory = (componentLib, name) ->
    instantiator = "new #{name}()"
    comp = componentLib.getComponent name
    if comp.type is "pure2"
      # XXX: can we get rid of this??
      t0 = componentLib.inputPortById(name, 0).ctype
      t1 = componentLib.inputPortById(name, 0).ctype
      instantiator = "new PureFunctionComponent2<" + name + "," + t0 + "," + t1 + ">"
    return """static Component *create() { return #{instantiator}; }
    static const char * const name = "#{name}";
    static const MicroFlo::ComponentId id = ComponentLibrary::get()->add(create, name);
    """

generateComponent = (lib, name, sourceFile) ->
    ports = microflo.generate.componentPorts lib, name
    factory = generateFactory lib, name
    return """namespace #{name} {
    #{ports}
    #include "#{sourceFile}"

    #{factory}
    } // end namespace #{name}"""

componentDefsCommand = (sourceFile, env) ->
    lib = new microflo.componentlib.ComponentLibrary()
    lib.loadFile sourceFile

    components = Object.keys lib.getComponents()
    if not components.length
        console.error "Could not find any MicroFlo components in #{sourceFile}"
        process.exit 1
    name = components[0]

    componentFile = sourceFile.replace(path.extname(sourceFile), ".component")
    includePath = "./" + path.basename sourceFile
    componentWrapper = generateComponent lib, name, includePath
    fs.writeFileSync componentFile, componentWrapper

graphCommand = (graphFile, env) ->
    lib = new microflo.componentlib.ComponentLibrary()
    lib.loadFile graphFile

    microflo.definition.loadFile graphFile, (err, graph) ->
        throw err if err
        graph = microflo.generate.initialCmdStream lib, graph
        fs.writeFileSync graphFile+".graph.h", graph

mainCommand = (inputFile, env) ->
    library = env.library or defaultLibrary
    componentLib = new microflo.componentlib.ComponentLibrary()
    componentLib.loadSetFile library, (err) ->
        throw err if err

        microflo.generate.generateMain componentLib, inputFile, env

main = ->
    commander.version module.exports.version
    commander.command("componentlib <JsonFile> <OutputPath> <FactoryMethodName>")
        .description("Generate compilable sources of specified component library from .json definition")
        .action generateComponentLib
    commander.command("update-defs")
        .description("Update internal generated definitions")
        .action updateDefsCommand
    commander.command("component <COMPONENT.hpp>")
        .description("Update generated definitions for component")
        .action componentDefsCommand
    commander.command("graph <COMPONENT.hpp>")
        .description("Update generated definitions for component")
        .option("-t, --target <platform>", "Target platform: arduino|linux|avr8")
        .action graphCommand
    commander.command("main <GRAPH>")
        .description("Generate an entrypoint file")
        .option("-t, --target <platform>", "Target platform: arduino|linux|avr8")
        .option("-m, --mainfile <FILE.hpp>", "File to include for providing main()")
        .option("-o, --output <FILE>", "File to output to. Defaults to $graphname.cpp")
        .option("-l, --library <FILE.json>", "Component library file") # WARN: to be deprecated
        .option("-d, --debug <level>", "Debug level to configure the runtime with. Default: Error")
        .option("--enable-maps", "Enable graph info maps")
        .action mainCommand

    commander.command("generate <INPUT> <OUTPUT>")
        .description("Generate MicroFlo firmware code, with embedded graph.")
        .option("-l, --library <FILE.json>", "Component library file")
        .option("-t, --target <platform>", "Target platform: arduino|linux|avr8")
        .action generateFwCommand
    commander.command("upload <GRAPH>")
        .option("-s, --serial <PORT>", "which serial port to use", String, 'auto')
        .option("-b, --baudrate <RATE>", "baudrate for serialport", Number, 9600)
        .option("-d, --debug <LEVEL>", "set debug level", String, 'Error')
        .option("-m, --componentmap <.json>", "Component mapping definition")
        .description("Upload a new graph to a device running MicroFlo firmware")
        .action uploadGraphCommand
    commander.command("runtime")
        .description("Run as a server, for use with the NoFlo UI.")
        .option("-s, --serial <PORT>", "which serial port to use")
        .option("-b, --baudrate <RATE>", "baudrate for serialport")
        .option("-d, --debug <LEVEL>", "set debug level")
        .option("-p, --port <PORT>", "which port to use for WebSocket")
        .option("-i, --ip <IP>", "which IP to use for WebSocket")
        .option("-f, --file <FILE>", "Firmware file to run (.js or binary)")
        .option("-m, --componentmap <.json>", "Component mapping definition")
        .action setupRuntimeCommand
    commander.command("register [USER]")
        .description("Register the runtime with Flowhub registry")
        .option("-p, --port <PORT>", "WebSocket port")
        .option("-i, --ip <IP>", "WebSocket IP")
        .option("-l, --label <PORT>", "Label to show in UI for this runtime")
        .option("-r, --id <RUNTIME-ID>", "UUID for the runtime")
        .action registerRuntimeCommand
    commander.command("flash <FILE.hex>")
        .description("Flash runtime onto device")
        .option("-s, --serial <PORT>", "which serial port to use")
        .option("-b, --baudrate <RATE>", "baudrate for serialport")
        .action flashCommand
    commander.parse process.argv
    commander.help()  if process.argv.length <= 2

exports.main = main
