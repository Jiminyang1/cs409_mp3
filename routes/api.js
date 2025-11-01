var mongoose = require('mongoose');
var User = require('../models/user');
var Task = require('../models/task');

function createError(status, message, data) {
    var error = new Error(message);
    error.status = status;
    error.data = data || {};
    return error;
}

function sendResponse(res, status, message, data) {
    res.status(status).json({
        message: message,
        data: data
    });
}

function handleError(res, error) {
    if (error.status) {
        return sendResponse(res, error.status, error.message, error.data || {});
    }
    if (error.name === 'ValidationError') {
        return sendResponse(res, 400, error.message, {});
    }
    if (error.name === 'CastError') {
        return sendResponse(res, 400, 'Invalid value for field "' + error.path + '"', {});
    }
    console.error(error);
    return sendResponse(res, 500, 'Internal server error', {});
}

function parseJSONParam(value, paramName) {
    if (value === undefined) {
        return undefined;
    }
    try {
        return JSON.parse(value);
    } catch (err) {
        throw createError(400, 'Invalid JSON in "' + paramName + '" parameter');
    }
}

function parseNumberParam(value, paramName) {
    if (value === undefined) {
        return undefined;
    }
    var parsed = Number(value);
    if (!Number.isInteger(parsed) || parsed < 0) {
        throw createError(400, 'Parameter "' + paramName + '" must be a non-negative integer');
    }
    return parsed;
}

function parseCountParam(value) {
    if (value === undefined) {
        return false;
    }
    if (typeof value === 'boolean') {
        return value;
    }
    if (typeof value === 'string') {
        return value.toLowerCase() === 'true';
    }
    return false;
}

function parseBoolean(value, defaultValue) {
    if (value === undefined || value === null) {
        return defaultValue;
    }
    if (typeof value === 'boolean') {
        return value;
    }
    if (typeof value === 'string') {
        var lower = value.toLowerCase();
        if (lower === 'true') {
            return true;
        }
        if (lower === 'false') {
            return false;
        }
    }
    return Boolean(value);
}

function parseDateValue(value, fieldName) {
    if (value === undefined || value === null || value === '') {
        return undefined;
    }
    // Accept both ISO strings and millisecond timestamps (number or numeric string)
    var date;
    if (typeof value === 'number') {
        date = new Date(value);
    } else if (typeof value === 'string') {
        // Try parsing as numeric timestamp first (including floats and scientific notation)
        var numValue = Number(value);
        if (!isNaN(numValue) && isFinite(numValue)) {
            date = new Date(numValue);
        } else {
            // Try parsing as ISO date string
            date = new Date(value);
        }
    } else {
        date = new Date(value);
    }
    if (Number.isNaN(date.getTime())) {
        throw createError(400, 'Invalid date supplied for "' + fieldName + '"');
    }
    return date;
}

function buildQueryOptions(req, options) {
    options = options || {};
    var filter = parseJSONParam(req.query.where, 'where') || {};
    var sort = parseJSONParam(req.query.sort, 'sort');
    var selectParamName = req.query.select !== undefined ? 'select' : (req.query.filter !== undefined ? 'filter' : 'select');
    var selectValue = req.query.select !== undefined ? req.query.select : req.query.filter;
    var select = parseJSONParam(selectValue, selectParamName);
    var skip = parseNumberParam(req.query.skip, 'skip');
    var limit = parseNumberParam(req.query.limit, 'limit');
    var count = parseCountParam(req.query.count);

    if (count && select) {
        throw createError(400, 'Cannot use "select" parameter when "count" is true');
    }

    if (!count) {
        if (limit === undefined && options.defaultLimit !== undefined) {
            limit = options.defaultLimit;
        }
    } else {
        limit = undefined;
    }

    return {
        filter: filter,
        sort: sort,
        select: select,
        skip: skip,
        limit: limit,
        count: count
    };
}

function normalizeIdArray(values, fieldName) {
    if (values === undefined || values === null) {
        return [];
    }
    if (!Array.isArray(values)) {
        values = [values];
    }
    var cleaned = values.filter(function (value) {
        return value !== undefined && value !== null && value !== '';
    }).map(String);
    var unique = Array.from(new Set(cleaned));
    unique.forEach(function (id) {
        if (!mongoose.Types.ObjectId.isValid(id)) {
            throw createError(400, 'Invalid task id in "' + fieldName + '" array');
        }
    });
    return unique;
}

async function ensureTasksExist(taskIds) {
    if (!taskIds.length) {
        return [];
    }
    var tasks = await Task.find({ _id: { $in: taskIds } });
    if (tasks.length !== taskIds.length) {
        throw createError(400, 'One or more tasks in pendingTasks do not exist');
    }
    return tasks;
}

async function removeTaskFromUser(taskId, userId) {
    if (!userId) {
        return;
    }
    await User.updateOne({ _id: userId }, { $pull: { pendingTasks: taskId } });
}

async function addTaskToUser(taskId, userId) {
    if (!userId) {
        return;
    }
    await User.updateOne({ _id: userId }, { $addToSet: { pendingTasks: taskId } });
}

async function syncUserPendingTasks(userDoc, previousPending) {
    var userId = userDoc._id.toString();
    var previousIds = (previousPending || []).map(String);
    var currentIds = (userDoc.pendingTasks || []).map(String);

    var currentSet = new Set(currentIds);
    var previousSet = new Set(previousIds);

    var removed = previousIds.filter(function (id) { return !currentSet.has(id); });
    var toEnsure = currentIds;

    if (removed.length) {
        await Task.updateMany({
            _id: { $in: removed },
            assignedUser: userId
        }, {
            $set: {
                assignedUser: '',
                assignedUserName: 'unassigned'
            }
        });
    }

    if (toEnsure.length) {
        var tasks = await Task.find({ _id: { $in: toEnsure } });
        for (var i = 0; i < tasks.length; i += 1) {
            var task = tasks[i];
            var previousUserId = task.assignedUser;
            if (previousUserId && previousUserId !== userId) {
                await removeTaskFromUser(task._id.toString(), previousUserId);
            }
            task.assignedUser = userId;
            task.assignedUserName = userDoc.name;
            if (task.completed) {
                task.completed = false;
            }
            await task.save();
        }
    }
}

async function unassignTask(taskDoc) {
    if (!taskDoc) {
        return;
    }
    var currentUserId = taskDoc.assignedUser;
    if (currentUserId) {
        await removeTaskFromUser(taskDoc._id.toString(), currentUserId);
    }
    taskDoc.assignedUser = '';
    taskDoc.assignedUserName = 'unassigned';
}

async function assignTask(taskDoc, userDoc) {
    if (!taskDoc || !userDoc) {
        return;
    }
    var userId = userDoc._id.toString();
    if (taskDoc.assignedUser && taskDoc.assignedUser !== userId) {
        await removeTaskFromUser(taskDoc._id.toString(), taskDoc.assignedUser);
    }
    taskDoc.assignedUser = userId;
    taskDoc.assignedUserName = userDoc.name;
}

module.exports = function (router) {
    router.route('/users')
        .get(async function (req, res) {
            try {
                var queryOptions = buildQueryOptions(req, {});
                if (queryOptions.count) {
                    var count = await User.countDocuments(queryOptions.filter);
                    return sendResponse(res, 200, 'OK', count);
                }
                var query = User.find(queryOptions.filter);
                if (queryOptions.select) {
                    query = query.select(queryOptions.select);
                }
                if (queryOptions.sort) {
                    query = query.sort(queryOptions.sort);
                }
                if (queryOptions.skip !== undefined) {
                    query = query.skip(queryOptions.skip);
                }
                if (queryOptions.limit !== undefined) {
                    query = query.limit(queryOptions.limit);
                }
                var users = await query.exec();
                return sendResponse(res, 200, 'OK', users);
            } catch (error) {
                return handleError(res, error);
            }
        })
        .post(async function (req, res) {
            try {
                var pendingTaskIds = normalizeIdArray(req.body.pendingTasks || [], 'pendingTasks');
                await ensureTasksExist(pendingTaskIds);

                var user = new User({
                    name: req.body.name,
                    email: req.body.email,
                    pendingTasks: pendingTaskIds
                });

                await user.save();
                await syncUserPendingTasks(user, []);

                var createdUser = await User.findById(user._id);
                return sendResponse(res, 201, 'User created', createdUser);
            } catch (error) {
                if (error.code === 11000) {
                    return sendResponse(res, 400, 'Email already exists', {});
                }
                return handleError(res, error);
            }
        });

    router.route('/users/:id')
        .get(async function (req, res) {
            try {
                var userId = req.params.id;
                if (!mongoose.Types.ObjectId.isValid(userId)) {
                    throw createError(400, 'Invalid user id');
                }
                var selectParamName = req.query.select !== undefined ? 'select' : (req.query.filter !== undefined ? 'filter' : 'select');
                var selectValue = req.query.select !== undefined ? req.query.select : req.query.filter;
                var select = parseJSONParam(selectValue, selectParamName);
                var query = User.findById(userId);
                if (select) {
                    query = query.select(select);
                }
                var user = await query.exec();
                if (!user) {
                    throw createError(404, 'User not found');
                }
                return sendResponse(res, 200, 'OK', user);
            } catch (error) {
                return handleError(res, error);
            }
        })
        .put(async function (req, res) {
            try {
                var userId = req.params.id;
                if (!mongoose.Types.ObjectId.isValid(userId)) {
                    throw createError(400, 'Invalid user id');
                }

                var user = await User.findById(userId);
                if (!user) {
                    throw createError(404, 'User not found');
                }

                var previousPending = (user.pendingTasks || []).slice();
                var pendingTaskIds = normalizeIdArray(req.body.pendingTasks || [], 'pendingTasks');
                await ensureTasksExist(pendingTaskIds);

                user.name = req.body.name;
                user.email = req.body.email;
                user.pendingTasks = pendingTaskIds;

                await user.save();
                await syncUserPendingTasks(user, previousPending);

                var updatedUser = await User.findById(userId);
                return sendResponse(res, 200, 'User updated', updatedUser);
            } catch (error) {
                if (error.code === 11000) {
                    return sendResponse(res, 400, 'Email already exists', {});
                }
                return handleError(res, error);
            }
        })
        .delete(async function (req, res) {
            try {
                var userId = req.params.id;
                if (!mongoose.Types.ObjectId.isValid(userId)) {
                    throw createError(400, 'Invalid user id');
                }

                var user = await User.findById(userId);
                if (!user) {
                    throw createError(404, 'User not found');
                }

                await Task.updateMany({ assignedUser: userId }, {
                    $set: {
                        assignedUser: '',
                        assignedUserName: 'unassigned'
                    }
                });

                await User.deleteOne({ _id: userId });

                return res.status(204).send();
            } catch (error) {
                return handleError(res, error);
            }
        });

    router.route('/tasks')
        .get(async function (req, res) {
            try {
                var queryOptions = buildQueryOptions(req, { defaultLimit: 100 });
                if (queryOptions.count) {
                    var count = await Task.countDocuments(queryOptions.filter);
                    return sendResponse(res, 200, 'OK', count);
                }
                if (queryOptions.limit === 0) {
                    return sendResponse(res, 200, 'OK', []);
                }
                var query = Task.find(queryOptions.filter);
                if (queryOptions.select) {
                    query = query.select(queryOptions.select);
                }
                if (queryOptions.sort) {
                    query = query.sort(queryOptions.sort);
                }
                if (queryOptions.skip !== undefined) {
                    query = query.skip(queryOptions.skip);
                }
                if (queryOptions.limit !== undefined) {
                    query = query.limit(queryOptions.limit);
                }
                var tasks = await query.exec();
                return sendResponse(res, 200, 'OK', tasks);
            } catch (error) {
                return handleError(res, error);
            }
        })
        .post(async function (req, res) {
            try {
                var assignedUserId = req.body.assignedUser ? String(req.body.assignedUser) : '';
                var userDoc = null;

                if (assignedUserId) {
                    if (!mongoose.Types.ObjectId.isValid(assignedUserId)) {
                        throw createError(400, 'Invalid user id in assignedUser');
                    }
                    userDoc = await User.findById(assignedUserId);
                    if (!userDoc) {
                        throw createError(400, 'Assigned user does not exist');
                    }
                }

                var completed = parseBoolean(req.body.completed, false);
                var deadlineValue = parseDateValue(req.body.deadline, 'deadline');

                var task = new Task({
                    name: req.body.name,
                    description: req.body.description === undefined ? '' : req.body.description,
                    deadline: deadlineValue,
                    completed: completed,
                    assignedUser: '',
                    assignedUserName: 'unassigned'
                });

                if (userDoc) {
                    await assignTask(task, userDoc);
                }

                await task.save();

                if (task.assignedUser && !task.completed) {
                    await addTaskToUser(task._id.toString(), task.assignedUser);
                }

                var createdTask = await Task.findById(task._id);
                return sendResponse(res, 201, 'Task created', createdTask);
            } catch (error) {
                return handleError(res, error);
            }
        });

    router.route('/tasks/:id')
        .get(async function (req, res) {
            try {
                var taskId = req.params.id;
                if (!mongoose.Types.ObjectId.isValid(taskId)) {
                    throw createError(400, 'Invalid task id');
                }
                var selectParamName = req.query.select !== undefined ? 'select' : (req.query.filter !== undefined ? 'filter' : 'select');
                var selectValue = req.query.select !== undefined ? req.query.select : req.query.filter;
                var select = parseJSONParam(selectValue, selectParamName);
                var query = Task.findById(taskId);
                if (select) {
                    query = query.select(select);
                }
                var task = await query.exec();
                if (!task) {
                    throw createError(404, 'Task not found');
                }
                return sendResponse(res, 200, 'OK', task);
            } catch (error) {
                return handleError(res, error);
            }
        })
        .put(async function (req, res) {
            try {
                var taskId = req.params.id;
                if (!mongoose.Types.ObjectId.isValid(taskId)) {
                    throw createError(400, 'Invalid task id');
                }

                var task = await Task.findById(taskId);
                if (!task) {
                    throw createError(404, 'Task not found');
                }

                var previousUserId = task.assignedUser;
                var completed = parseBoolean(req.body.completed, false);
                var assignedUserId = req.body.assignedUser ? String(req.body.assignedUser) : '';
                var userDoc = null;
                var deadlineValue = parseDateValue(req.body.deadline, 'deadline');

                if (assignedUserId) {
                    if (!mongoose.Types.ObjectId.isValid(assignedUserId)) {
                        throw createError(400, 'Invalid user id in assignedUser');
                    }
                    userDoc = await User.findById(assignedUserId);
                    if (!userDoc) {
                        throw createError(400, 'Assigned user does not exist');
                    }
                }

                task.name = req.body.name;
                task.description = req.body.description === undefined ? '' : req.body.description;
                task.deadline = deadlineValue;
                task.completed = completed;

                if (userDoc) {
                    await assignTask(task, userDoc);
                } else {
                    await unassignTask(task);
                }

                await task.save();

                if (previousUserId && previousUserId !== (userDoc ? userDoc._id.toString() : '')) {
                    await removeTaskFromUser(taskId, previousUserId);
                }

                if (task.assignedUser) {
                    if (task.completed) {
                        await removeTaskFromUser(taskId, task.assignedUser);
                    } else {
                        await addTaskToUser(taskId, task.assignedUser);
                    }
                }

                var updatedTask = await Task.findById(taskId);
                return sendResponse(res, 200, 'Task updated', updatedTask);
            } catch (error) {
                return handleError(res, error);
            }
        })
        .delete(async function (req, res) {
            try {
                var taskId = req.params.id;
                if (!mongoose.Types.ObjectId.isValid(taskId)) {
                    throw createError(400, 'Invalid task id');
                }

                var task = await Task.findById(taskId);
                if (!task) {
                    throw createError(404, 'Task not found');
                }

                var assignedUserId = task.assignedUser;
                await Task.deleteOne({ _id: taskId });

                if (assignedUserId) {
                    await removeTaskFromUser(taskId, assignedUserId);
                }

                return res.status(204).send();
            } catch (error) {
                return handleError(res, error);
            }
        });
};

