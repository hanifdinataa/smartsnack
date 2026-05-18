<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Validation\ValidationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use App\Http\Middleware\ForceJsonResponse;
use App\Http\Middleware\Authenticate;


return Application::configure(basePath: dirname(__DIR__))
    ->withCommands([
        __DIR__ . '/../app/Console/Commands',
    ])
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware) {
        $middleware->alias([
            'force.json' => ForceJsonResponse::class,
            'auth' => Authenticate::class,
        ]);

        $middleware->appendToGroup('api', [
            'force.json',
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions) {
        // 422: Validation errors
        $exceptions->renderable(function (ValidationException $e, $request) {
            if ($request->expectsJson() || $request->is('api/*')) {
                return errorResponse('Validation error', $e->errors(), 422);
            }
        });

        // 401: Unauthorized
        $exceptions->renderable(function (AuthenticationException $e, $request) {
            if ($request->expectsJson() || $request->is('api/*')) {
                return errorResponse('Unauthorized', null, 401);
            }
        });

        // 403: Forbidden / Access denied
        $exceptions->renderable(function (AccessDeniedHttpException $e, $request) {
            if ($request->expectsJson() || $request->is('api/*')) {
                return errorResponse('Forbidden access', null, 403);
            }
        });

        // 404: Not found (Model or Route)
        $exceptions->renderable(function (NotFoundHttpException | ModelNotFoundException $e, $request) {
            if ($request->expectsJson() || $request->is('api/*')) {
                return errorResponse('Data not found', null, 404);
            }
        });

        // 500: Other unhandled errors
        $exceptions->renderable(function (Throwable $e, $request) {
            if (($request->expectsJson() || $request->is('api/*')) && !($e instanceof HttpExceptionInterface)) {
                return errorResponse('Server error', ['exception' => $e->getMessage()], 500);
            }
        });
    })
    ->create();
