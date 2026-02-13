const express = require('express');
const cors = require('cors');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();

// CORS middleware
app.use(cors({
    origin: ['http://127.0.0.1:5505', 'http://localhost:5505'], // Your admin interface
    credentials: true
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

// Proxy middleware for OpenRouteService
app.use('/openrouteservice', createProxyMiddleware({
    target: 'https://api.openrouteservice.org',
    changeOrigin: true,
    pathRewrite: {
        '^/openrouteservice/(.*)': '/$1'
    },
    onProxyReq: (proxyReq, req, res) => {
        // Add CORS headers to the response
        res.setHeader('Access-Control-Allow-Origin', req.headers.origin || '*');
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With');
        res.setHeader('Access-Control-Allow-Credentials', 'true');
    }
}));

app.listen(3001, () => {
    console.log('🚀 Proxy server running on port 3001');
    console.log('📡 OpenRouteService proxy: http://localhost:3001/openrouteservice');
    console.log('🔧 Update your admin interface to use: http://localhost:3001/openrouteservice');
});
