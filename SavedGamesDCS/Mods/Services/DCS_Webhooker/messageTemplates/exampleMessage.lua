-- Assumes "default" webhook configured in environment variables
Webhooker.Server.addTemplate (
"example", -- Handle for the template, pass this to Webhooker.send
"default", -- Handle for webhook URL as configured in environment variable
[[
    {
        "username":"ExampleBot %3 ",
        "content":"Hello from template  \nPercent: %% \n string: %1 \n int: %2 \n list: %4 \n Table:\n Col1 | Col 2 | Col3\n----|----|----\n%5 "
    }
]]) 

Webhooker.Server.addString("substringExample","Was Substituted")
