confLoader = require "confLoader"
settings = require "imapfilterSettings"

conftab = confLoader.scandir( settings.configFolder )
print ( "Spam Filter found " ..#conftab .." Config Files!" )

for i, confFile in ipairs( conftab ) do
    print( "Handling config file " ..i .. " - " .. confFile )
    
    -- Fehlerbehandlung für Dateizugriff
    local file = io.open(confFile, "r")
    if not file then
        print( "✗ ERROR: Config file not found: " .. confFile )
        goto continue
    end
    file:close()
    print( "✓ Config file exists: " .. confFile )
    
    -- Scope-Problem lösen: Alles in einen do-Block
    do
        local config = nil
        local success, err = pcall(function()
            config = confLoader.readConf( confFile )
        end)
        
        if not success then
            print( "✗ ERROR reading config: " .. tostring(err) )
            break -- Verlasse den do-Block, dann goto continue
        end
        
        if config == nil then
            print( "✗ ERROR: Config is nil" )
            break
        end
        
        print( "✓ Config loaded successfully" )
        
        -- Prüfe spamHandling
        if confLoader.tableHasKey( config, "spamHandling" ) and config.spamHandling ~= "yes" then
            print( "   Spam handling disabled" )
            break
        end
        
        print( "✓ Spam handling enabled" )
        
        -- Validiere erforderliche Parameter
        if not config.server or not config.username or not config.password then
            print( "✗ ERROR: Missing required config parameters" )
            break
        end
        
        print( "   Server: " .. config.server )
        print( "   Username: " .. config.username )
        
        -- IMAP-Verbindung
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
            break
        end
        
        print( "✓ IMAP connection established" )
        
        -- Umgebungsvariablen
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
            print( "   Processing spam subject: " .. config.spamSubject )
            
            local spamMessages = nil
            success, err = pcall(function()
                spamMessages = imapObj[config.folders.inbox]:contain_subject( config.spamSubject )
            end)
            
            if not success then
                print( "✗ ERROR filtering spam: " .. tostring(err) )
                break
            end
            
            if spamMessages and #spamMessages > 0 then
                success, err = pcall(function()
                    imapObj[config.folders.inbox]:move_messages( imapObj[config.folders.spam], spamMessages )
                end)
                
                if not success then
                    print( "✗ ERROR moving spam: " .. tostring(err) )
                    break
                end
                
                print( "✓ Moved " .. #spamMessages .. " spam messages" )
            else
                print( "   0 spam messages found" )
            end
        end
        
        -- Report-Einstellung
        local report = "--noreport"
        if confLoader.tableHasKey( config, "report" ) and config.report == "yes" then
            report = ""
            print( "   Report enabled" )
        end
        
        -- Kommando ausführen
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
        
        print( "   Executing spam filter..." )
        success, err = pcall(function()
            os.execute( command )
        end)
        
        if not success then
            print( "✗ ERROR executing command: " .. tostring(err) )
            break
        end
        
        print( "✓ Command executed successfully" )
        
    end -- Ende des do-Blocks
    
    ::continue::
    print( "Completed processing: " .. confFile )
    print( "----------------------------------------" )
end

print( "Spam filter processing completed!" )
