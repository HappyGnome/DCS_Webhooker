--[[
   Copyright 2023 HappyGnome (https://github.com/HappyGnome)

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
--]]

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
