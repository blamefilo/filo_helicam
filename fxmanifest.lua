fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'filo_helicam'
original_author 'ZeroFour04'
author 'filo studios.'
description 'A FiveM helicoper camera script'
discord 'https://discord.gg/bErPEKvRXg'

version '1.0.1'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'version_check.lua',
    'server.lua',
}

client_scripts {
    'client.lua',
}