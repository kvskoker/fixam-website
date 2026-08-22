const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 6000;

app.use(express.static(path.join(__dirname, 'public')));

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/privacy', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'privacy.html'));
});

app.get('/terms', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'terms.html'));
});

app.listen(PORT, () => {
    console.log(`Fixam website running on http://localhost:${PORT}`);
});
