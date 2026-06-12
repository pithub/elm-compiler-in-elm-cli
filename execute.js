"use strict";

const http = require('http');
const path = require('path');

global.XMLHttpRequest = require('xhr2');
const scriptModule = (() => {
    const originalWarn = console.warn;
    console.warn = () => { };
    const module = require(path.join(__dirname, 'elm.js'));
    console.warn = originalWarn;
    return module;
})();

const server = http.createServer(async (req, res) => {
    const url = decodeURIComponent(req.url);

    const chunks = [];
    for await (const chunk of req) {
        chunks.push(chunk);
    }
    const content = Buffer.concat(chunks);

    process.stdout.write(content.toString());

    server.close();
    process.exit();
});

server.listen(0, "localhost", () => {
    const flags = {
        cwd: process.cwd(),
        serverPort: server.address().port,
    };
    Object.values(scriptModule.Elm)[0].init({ flags });
});
