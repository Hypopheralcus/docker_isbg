confLoader = require "confLoader"
settings = require "imapfilterSettings"

conftab = confLoader.scandir( settings.configFolder )
print ( "Spam Filter found " ..#conftab .." Config Files!" )

for i, confFile in ipairs( conftab ) do
    print( "Handling config file " ..i .. " - " .. confFile )
    
    -- Überprüfe ob die Datei existiert
    local file = io.open(confFile, "r")
    if file then
        print( "✓ Config file exists and is readable: " .. confFile )
        file:close()
    else
        print( "✗ ERROR: Config file not found or not readable: " .. confFile )
        goto continue
    end
    
    -- Lade die Konfiguration mit Fehlerbehandlung
    local config = nil
    local success, err = pcall(function()
        config = confLoader.readConf( confFile )
    end)
    
    if not success then
        print( "✗ ERROR reading config file " .. confFile .. ": " .. tostring(err) )
        goto continue
    end
    
    if config == nil then
        print( "✗ ERROR: Config is nil for file: " .. confFile )
        goto continue
    end
    
    print( "✓ Config loaded successfully for file: " .. confFile )
    
    -- Prüfe spamHandling
    local spamHandlingEnabled = true
    if confLoader.tableHasKey( config, "spamHandling" ) then
        spamHandlingEnabled = (config.spamHandling == "yes")
        print( "   spamHandling setting: " .. tostring(config.spamHandling) )
    else
        print( "   spamHandling not specified, defaulting to 'yes'" )
    end
    
    if spamHandlingEnabled then
        print( "✓ Spam handling enabled for config: " .. confFile )
        
        -- Prüfe erforderliche Konfigurationsparameter
        if not config.server then
            print( "✗ ERROR: Missing server configuration in: " .. confFile )
            goto continue
        end
        if not config.username then
            print( "✗ ERROR: Missing username configuration in: " .. confFile )
            goto continue
        end
        if not config.password then
            print( "✗ ERROR: Missing password configuration in: " .. confFile )
            goto continue
        end
        
        print( "   Server: " .. config.server )
        print( "   Username: " .. config.username )
        print( "   Password: [HIDDEN]" )
        
        -- IMAP-Verbindung mit Fehlerbehandlung
        local imapObj = nil
        success, err = pcall(function()
            imapObj = IMAP {
                server = config.server,
                username = config.username,
                password = config.password,
                ssl = "ssl3"
            }
        end)
        
        if not success then
            print( "✗ ERROR creating IMAP connection: " .. tostring(err) )
            goto continue
        end
        
        print( "✓ IMAP connection established" )
        
        -- Umgebungsvariablen prüfen
        local verboseOption = ""
        if os.getenv( "DETAILED_LOGGING" ) == "true" then 
            verboseOption = " --verbose"
            print( "   Verbose logging enabled" )
        end
        
        local gmailOption = ""
        if confLoader.tableHasKey( config, "isGmail" ) and config.isGmail == "yes" then 
            gmailOption = " --gmail"
            print( "   Gmail mode enabled" )
        end
        
        local batchSize = os.getenv( "FILTER_BATCH_SIZE" )
        local maxMailSize = os.getenv( "MAX_MAIL_SIZE" )
        
        print( "   Batch size: " .. tostring(batchSize) )
        print( "   Max mail size: " .. tostring(maxMailSize) )
        
        -- Spam-Subject-Handling
        if confLoader.tableHasKey( config, "spamSubject" ) then
            print( "   Processing spam subject filter: " .. config.spamSubject )
            
            local spamMessages = nil
            success, err = pcall(function()
                spamMessages = imapObj[config.folders.inbox]:contain_subject( config.spamSubject )
            end)
            
            if not success then
                print( "✗ ERROR filtering spam messages: " .. tostring(err) )
                goto continue
            end
            
            if spamMessages and #spamMessages > 0 then
                print( "   Found " .. #spamMessages .. " spam messages to move" )
                
                success, err = pcall(function()
                    imapObj[config.folders.inbox]:move_messages( imapObj[config.folders.spam], spamMessages )
                end)
                
                if not success then
                    print( "✗ ERROR moving spam messages: " .. tostring(err) )
                    goto continue
                end
                
                print( "✓ Moved " .. #spamMessages .. " spam messages" )
            else
                print( "   0 spam messages found to move" )
            end
        end
        
        -- Report-Einstellung
        local report = "--noreport"
        if confLoader.tableHasKey( config, "report" ) and config.report == "yes" then
            report = ""
            print( "   Report enabled" )
        else
            print( "   Report disabled" )
        end
        
        -- Kommando zusammenbauen
        local command = "su -c \"" .. settings.isbgPath .. 
                       " --imaphost " .. config.server .. 
                       " --spamc --imapuser " .. config.username .. 
                       " --partialrun " .. batchSize .. 
                       " --maxsize " .. maxMailSize .. 
                       " " .. report .. 
                       " --delete --expunge --spaminbox " .. config.folders.spam .. 
                       " --passwdfilename " .. confFile .. 
                       verboseOption .. gmailOption .. 
                       " \" $USERNAME"
        
        if os.getenv( "DETAILED_LOGGING" ) == "true" then
            print( "   Command: " .. command )
        end
        
        print( "   Executing spam filter command..." )
        
        -- Kommando ausführen mit Fehlerbehandlung
        success, err = pcall(function()
            os.execute( command )
        end)
        
        if not success then
            print( "✗ ERROR executing command: " .. tostring(err) )
            goto continue
        end
        
        print( "✓ Command executed successfully" )
        
    else
        print( "   Spam handling disabled for config: " .. confFile )
    end
    
    ::continue::
    print( "Completed processing config file " .. i .. " - " .. confFile )
    print( "----------------------------------------" )
end

print( "Spam filter processing completed!" )
