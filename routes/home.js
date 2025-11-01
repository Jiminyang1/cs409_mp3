module.exports = function (router) {
    router.route('/').get(function (req, res) {
        res.json({
            message: 'Welcome to the Llama.io API. Refer to the documentation for available endpoints.',
            data: {}
        });
    });
};
