"use strict";

const fs = require('fs').promises;
const http = require('http');
const os = require('os');
const path = require('path');
const readline = require('readline');

global.XMLHttpRequest = require('xhr2');
const scriptModule = (() => {
    const originalWarn = console.warn;
    console.warn = () => { };
    const module = require(path.join(__dirname, 'elm.js'));
    console.warn = originalWarn;
    return module;
})();

const promptSeparator = '\u241F'; // Symbol For Unit Separator

function getElmHome() {
    if (process.env.ELM_HOME) {
        return process.env.ELM_HOME;
    } else if (process.platform === 'win32') {
        return path.join(process.env.APPDATA, 'elm');
    } else {
        return path.join(os.homedir(), '.elm');
    }
}

const server = http.createServer(async (req, res) => {
    const url = decodeURIComponent(req.url);

    const chunks = [];
    for await (const chunk of req) {
        chunks.push(chunk);
    }
    const content = Buffer.concat(chunks);

    // URL routes:
    // c: create dir
    // d: delete file or dir
    // e: write to stderr
    // i: input from stdin
    // j: evaluate javascript
    // m: get mtime
    // o: write to stdout
    // r: read file
    // w: write file
    // x: exit with code

    if (url === '/i') {
        const promptAndPrefill = content.toString();
        let index = promptAndPrefill.indexOf(promptSeparator);
        if (index === -1) index = promptAndPrefill.length;

        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        let expectedClose = false;
        rl.on('close', () => {
            if (expectedClose) {
                // Do nothing, we already responded to the client
            } else {
                res.writeHead(200);
                res.end('d');
            }
        });
        rl.on('SIGINT', () => {
            res.writeHead(200);
            res.end('c');
            expectedClose = true;
            rl.close();
        });
        rl.question(promptAndPrefill.substring(0, index), (answer) => {
            res.writeHead(200);
            res.end('o' + answer);
            expectedClose = true;
            rl.close();
        });
        rl.write(promptAndPrefill.substring(index + 1));

    } else if (url === '/o') {
        process.stdout.write(content.toString());
        res.writeHead(200);
        res.end();

    } else if (url === '/e') {
        process.stderr.write(content.toString());
        res.writeHead(200);
        res.end();

    } else if (url.startsWith('/m')) {
        let mtime;
        try {
            const stats = await fs.stat(url.slice(2));
            mtime = stats.isDirectory() ?
                -Math.trunc(stats.mtimeMs) :
                Math.trunc(stats.mtimeMs);
        } catch (error) {
            mtime = 0;
        }
        res.writeHead(200);
        res.end(mtime.toString());

    } else if (url.startsWith('/r')) {
        try {
            const fileContent = await fs.readFile(url.slice(2));
            res.writeHead(200);
            res.end(fileContent);
        } catch (error) {
            res.writeHead(404);
            res.end();
        }

    } else if (url.startsWith('/w')) {
        await fs.writeFile(url.slice(2), content);
        res.writeHead(200);
        res.end();

    } else if (url.startsWith('/c')) {
        await fs.mkdir(url.slice(2), { recursive: true })
        res.writeHead(200);
        res.end();

    } else if (url.startsWith('/d')) {
        await fs.rm(url.slice(2), { force: true });
        res.writeHead(200);
        res.end();

    } else if (url.startsWith('/j')) {
        try {
            const result = eval(content.toString());
            res.writeHead(200);
            res.end('o' + result.toString());
        } catch (error) {
            res.writeHead(200);
            res.end('e' + error.toString());
        }

    } else if (url.startsWith('/x')) {
        server.close();
        process.exit(url.slice(2));

    } else {
        process.stderr.write('Unknown request ' + url + '\n');
        server.close();
        process.exit(1);
    }
});

server.listen(0, "localhost", () => {
    const flags = {
        args: process.argv.slice(2),
        cwd: process.cwd(),
        elmHome: getElmHome(),
        promptSeparator,
        serverPort: server.address().port,
        stderrIsTty: !!process.stderr.isTTY,
        stdoutIsTty: !!process.stdout.isTTY,
    };
    Object.values(scriptModule.Elm)[0].init({ flags });
});
