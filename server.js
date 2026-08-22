const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 6000;

const PUBLIC_DIR = path.join(__dirname, 'public');

// Pages keyed by the clean URL they are served at. Each is also reachable at
// its .html path, so both forms go through the same renderer.
const PAGES = {
    '/': 'index.html',
    '/privacy': 'privacy.html',
    '/terms': 'terms.html'
};

// The copyright year is injected at request time rather than hardcoded in the
// markup, so it stays correct without anyone editing the HTML each January.
const YEAR_PLACEHOLDER = /(<span class="copyright-year">)[^<]*(<\/span>)/g;

function sendPage(file, res, next) {
    fs.readFile(path.join(PUBLIC_DIR, file), 'utf8', (err, html) => {
        if (err) return next(err);
        res.type('html').send(
            html.replace(YEAR_PLACEHOLDER, `$1${new Date().getFullYear()}$2`)
        );
    });
}

// Registered before express.static so the .html paths are rendered too.
Object.entries(PAGES).forEach(([route, file]) => {
    const handler = (req, res, next) => sendPage(file, res, next);
    app.get(route, handler);
    app.get(`/${file}`, handler);
});

app.use(express.static(PUBLIC_DIR));

app.listen(PORT, () => {
    console.log(`Fixam website running on http://localhost:${PORT}`);
});
